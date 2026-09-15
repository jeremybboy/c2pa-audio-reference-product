#include "GenerationService.h"
#include "PluginProcessor.h"
#include "C2PASigningService.h"

#include <juce_audio_formats/juce_audio_formats.h>
#include <juce_gui_basics/juce_gui_basics.h>

#include <cmath>
#include <iostream>
#include <memory>

namespace
{
int fail(int code, const juce::String& message)
{
    std::cerr << message << '\n';
    return code;
}

bool writeTone(const juce::File& file)
{
    constexpr double sampleRate = 44100.0;
    constexpr int samples = 44100;
    juce::AudioBuffer<float> audio(2, samples);
    for (int channel = 0; channel < audio.getNumChannels(); ++channel)
        for (int sample = 0; sample < samples; ++sample)
            audio.setSample(
                channel,
                sample,
                0.4f * std::sin(
                    juce::MathConstants<double>::twoPi * 220.0
                    * static_cast<double>(sample) / sampleRate));
    std::unique_ptr<juce::OutputStream> stream = file.createOutputStream();
    juce::WavAudioFormat format;
    const auto options = juce::AudioFormatWriterOptions()
        .withSampleRate(sampleRate)
        .withNumChannels(2)
        .withBitsPerSample(24);
    auto writer = format.createWriterFor(stream, options);
    return writer != nullptr
        && writer->writeFromAudioSampleBuffer(audio, 0, audio.getNumSamples());
}

class TestPlayHead final : public juce::AudioPlayHead
{
public:
    juce::Optional<PositionInfo> getPosition() const override { return position; }
    PositionInfo position;
};
}

int main()
{
    juce::ScopedJuceInitialiser_GUI initialiseJuce;
    const auto root = juce::File::getCurrentWorkingDirectory()
        .getChildFile("loop-generator-vst3-tests-" + juce::Uuid().toString());
    if (const auto result = root.createDirectory(); result.failed())
        return fail(1, "Could not create test directory " + root.getFullPathName()
            + ": " + result.getErrorMessage());
    struct Cleanup { juce::File file; ~Cleanup() { file.deleteRecursively(); } } cleanup { root };

    loopgenerator::GenerationRequest request;
    request.prompt = "warm pad";
    request.instrument = "Synth";
    request.bars = 2;
    request.bpm = 120.0;
    if (request.validate().failed() || std::abs(request.durationSeconds() - 4.0) > 0.0001)
        return fail(2, "Bar duration did not follow host tempo.");
    request.bars = 4;
    request.bpm = 60.0;
    if (request.validate().wasOk())
        return fail(3, "Unsupported Stable Audio duration was accepted.");

    const auto fixture = root.getChildFile("fixture.wav");
    if (! writeTone(fixture))
        return fail(4, "Could not write WAV fixture.");
    loopgenerator::GeneratedLoopStore store;
    if (store.load(fixture, 2, 120.0).failed())
        return fail(5, "Generated WAV did not load.");
    const auto loaded = store.snapshot();
    if (loaded == nullptr || loaded->audio.getNumChannels() != 2
        || loaded->audio.getNumSamples() != 44100 || loaded->bars != 2)
        return fail(6, "Loaded loop metadata is incorrect.");

    loopgenerator::RuntimeConfiguration commandRuntime {
        juce::File("/runtime/python"),
        juce::File("/runtime/infer.py"),
        juce::File("/runtime/model cache")
    };
    request.bars = 2;
    request.bpm = 120.0;
    const auto command = loopgenerator::StableAudioGenerationService::commandArguments(
        commandRuntime,
        request,
        root.getChildFile("output.wav"),
        root.getChildFile("output.json"));
    if (! command.contains("Synth loop, warm pad")
        || ! command.contains("HF_HUB_CACHE=/runtime/model cache"))
        return fail(7, "Generation command did not preserve argument boundaries.");

    const auto tool = root.getChildFile("c2patool");
    const auto signingBundle = root.getChildFile("test-signing-bundle.pem");
    const auto trustAnchors = root.getChildFile("test-root.pem");
    const auto trustConfig = root.getChildFile("store.cfg");
    const auto metadata = root.getChildFile("model.json");
    tool.replaceWithText("test tool");
    signingBundle.replaceWithText("-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----\n");
    trustAnchors.replaceWithText("test root");
    trustConfig.replaceWithText("test config");
    metadata.replaceWithText(R"json({
        "modelName": "Stable Audio Open Small",
        "modelVersion": "test-revision"
    })json");
    loopgenerator::C2PASigningConfiguration signingConfiguration {
        tool, signingBundle, trustAnchors, trustConfig
    };
    int toolCalls = 0;
    juce::String observedManifest;
    loopgenerator::C2PASigningService signingService(
        signingConfiguration,
        [&toolCalls, &observedManifest](const juce::StringArray& arguments)
        {
            ++toolCalls;
            const auto outputIndex = arguments.indexOf("--output");
            if (outputIndex >= 0)
            {
                const auto manifestIndex = arguments.indexOf("--manifest");
                observedManifest = juce::File(arguments[manifestIndex + 1])
                    .loadFileAsString();
                const auto source = juce::File(arguments[1]);
                const auto destination = juce::File(arguments[outputIndex + 1]);
                return loopgenerator::C2PAToolResult {
                    source.copyFileTo(destination) ? 0 : 1,
                    "signed"
                };
            }
            return loopgenerator::C2PAToolResult { 0, R"json({
                "validation_state": "Trusted",
                "validation_results": {
                    "activeManifest": {
                        "success": [
                            { "code": "signingCredential.trusted" },
                            { "code": "claimSignature.validated" },
                            { "code": "assertion.dataHash.match" }
                        ],
                        "failure": []
                    }
                },
                "assertion": {
                    "action": "c2pa.created",
                    "digitalSourceType": "trainedAlgorithmicMedia"
                }
            })json" };
        });
    if (auto result = signingService.signAndValidate(fixture, metadata); result.failed())
        return fail(8, "C2PA signing pipeline failed: " + result.getErrorMessage());
    if (toolCalls != 2
        || ! observedManifest.contains("Loop Generator/")
        || ! observedManifest.contains("Stable Audio Open Small")
        || ! observedManifest.contains("c2pa.created")
        || ! observedManifest.contains(signingBundle.getFullPathName()))
        return fail(9, "C2PA manifest or sign/validate command sequence is incorrect.");

    if (juce::SystemStats::getEnvironmentVariable(
            "LOOP_GENERATOR_C2PA_LIVE_TEST", {}) == "1")
    {
        juce::String configurationError;
        const auto liveConfiguration =
            loopgenerator::C2PASigningConfiguration::discover(configurationError);
        if (! liveConfiguration)
            return fail(10, "Live C2PA configuration failed: " + configurationError);
        const auto requestedLiveWav = juce::SystemStats::getEnvironmentVariable(
            "LOOP_GENERATOR_C2PA_LIVE_WAV", {});
        const auto requestedLiveMetadata = juce::SystemStats::getEnvironmentVariable(
            "LOOP_GENERATOR_C2PA_LIVE_METADATA", {});
        const auto liveSource = requestedLiveWav.isNotEmpty()
            ? juce::File(requestedLiveWav) : fixture;
        const auto liveMetadata = requestedLiveMetadata.isNotEmpty()
            ? juce::File(requestedLiveMetadata) : metadata;
        const auto liveWav = root.getChildFile("live-c2pa.wav");
        if (! liveSource.copyFileTo(liveWav))
            return fail(11, "Could not prepare the live C2PA WAV fixture.");
        loopgenerator::C2PASigningService liveSigningService(*liveConfiguration);
        if (auto result = liveSigningService.signAndValidate(liveWav, liveMetadata);
            result.failed())
            return fail(12, "Live C2PA sign/validate failed: " + result.getErrorMessage());
        std::cout << "live C2PA signing passed\n";
    }

    loopgenerator::LoopGeneratorAudioProcessor processor;
    processor.prepareToPlay(48000.0, 512);
    if (processor.loadGeneratedAudio(fixture, 2, 120.0).failed())
        return fail(13, "Processor did not accept a generated WAV.");
    processor.parameters().getParameter(loopgenerator::parameter::sync)
        ->setValueNotifyingHost(0.0f);
    processor.setPreviewPlaying(true);
    juce::AudioBuffer<float> output(2, 512);
    output.clear();
    juce::MidiBuffer midi;
    processor.processBlock(output, midi);
    if (output.getRMSLevel(0, 0, output.getNumSamples()) <= 0.01f)
        return fail(14, "Preview playback did not produce audio.");

    TestPlayHead playHead;
    playHead.position.setIsPlaying(true);
    playHead.position.setBpm(128.0);
    playHead.position.setTimeSignature(
        juce::AudioPlayHead::TimeSignature { 4, 4 });
    playHead.position.setPpqPosition(0.0);
    processor.setPlayHead(&playHead);
    processor.parameters().getParameter(loopgenerator::parameter::sync)
        ->setValueNotifyingHost(1.0f);
    output.clear();
    processor.processBlock(output, midi);
    if (output.getRMSLevel(0, 0, output.getNumSamples()) <= 0.01f
        || std::abs(processor.currentHostBpm() - 128.0) > 0.001)
        return fail(15, "Host-synchronized playback did not produce audio.");

    juce::MemoryBlock state;
    processor.getStateInformation(state);
    loopgenerator::LoopGeneratorAudioProcessor restored;
    restored.setStateInformation(state.getData(), static_cast<int>(state.getSize()));
    restored.prepareToPlay(48000.0, 512);
    restored.parameters().getParameter(loopgenerator::parameter::sync)
        ->setValueNotifyingHost(0.0f);
    restored.setPreviewPlaying(true);
    output.clear();
    restored.processBlock(output, midi);
    if (state.isEmpty() || restored.generatedFile() != fixture
        || output.getRMSLevel(0, 0, output.getNumSamples()) <= 0.01f)
        return fail(16, "VST3 state did not restore the generated loop.");

    if (juce::SystemStats::getEnvironmentVariable(
            "LOOP_GENERATOR_VST3_LIVE_TEST", {}) == "1")
    {
        loopgenerator::LoopGeneratorAudioProcessor liveProcessor;
        liveProcessor.prepareToPlay(48000.0, 512);
        if (! liveProcessor.runtimeIsReady())
            return fail(17, "Installed Stable Audio runtime was not discovered: "
                + liveProcessor.statusText());
        liveProcessor.parameters().getParameter(loopgenerator::parameter::bars)
            ->setValueNotifyingHost(0.0f);
        if (! liveProcessor.requestGeneration(
                "Synth", "warm analog pulse, instrumental, 120 BPM", 424242))
            return fail(18, "Live generation request was rejected: "
                + liveProcessor.statusText());
        const auto deadline = juce::Time::getMillisecondCounterHiRes() + 240000.0;
        while (liveProcessor.isGenerating()
               && juce::Time::getMillisecondCounterHiRes() < deadline)
            juce::Thread::sleep(50);
        if (liveProcessor.isGenerating())
            return fail(19, "Live Stable Audio generation timed out.");
        if (! liveProcessor.generatedFile().existsAsFile())
            return fail(20, "Live Stable Audio generation failed: "
                + liveProcessor.statusText());
        liveProcessor.parameters().getParameter(loopgenerator::parameter::sync)
            ->setValueNotifyingHost(0.0f);
        liveProcessor.setPreviewPlaying(true);
        output.clear();
        liveProcessor.processBlock(output, midi);
        if (output.getRMSLevel(0, 0, output.getNumSamples()) <= 0.001f)
            return fail(21, "Live generated WAV produced no preview audio.");
        std::cout << "live generation passed: "
                  << liveProcessor.generatedFile().getFullPathName() << '\n';
    }

    std::cout << "duration, command isolation, WAV loading, preview, host sync, and state passed\n";
    return 0;
}
