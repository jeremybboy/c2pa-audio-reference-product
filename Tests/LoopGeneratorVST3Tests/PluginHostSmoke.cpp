#include "PluginProcessor.h"

#include <juce_audio_formats/juce_audio_formats.h>
#include <juce_audio_processors/juce_audio_processors.h>
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
        .getChildFile("loop-generator-vst3-host-" + juce::Uuid().toString());
    if (const auto result = root.createDirectory(); result.failed())
        return fail(1, "Host test directory could not be created: "
            + result.getErrorMessage());
    struct Cleanup { juce::File file; ~Cleanup() { file.deleteRecursively(); } } cleanup { root };
    const juce::File bundle(LOOP_GENERATOR_TEST_VST3);
    if (! bundle.isDirectory())
        return fail(1, "Loop Generator VST3 bundle was not built.");

    juce::VST3PluginFormat format;
    juce::OwnedArray<juce::PluginDescription> descriptions;
    format.findAllTypesForFile(descriptions, bundle.getFullPathName());
    auto* description = descriptions.isEmpty() ? nullptr : descriptions.getFirst();
    if (description == nullptr || description->name != "Loop Generator"
        || description->pluginFormatName != "VST3" || description->isInstrument)
        return fail(2, "Bundle was not discovered as a VST3 audio effect.");

    juce::String error;
    auto instance = format.createInstanceFromDescription(*description, 48000.0, 512, error);
    if (instance == nullptr)
        return fail(3, "VST3 could not be instantiated: " + error);
    instance->prepareToPlay(48000.0, 512);
    std::unique_ptr<juce::AudioProcessorEditor> editor(instance->createEditorIfNeeded());
    if (editor == nullptr)
        return fail(4, "VST3 editor could not be created.");

    juce::MemoryBlock state;
    instance->getStateInformation(state);
    if (state.isEmpty())
        return fail(5, "VST3 returned no persistent state.");

    juce::AudioBuffer<float> buffer(2, 512);
    for (int channel = 0; channel < buffer.getNumChannels(); ++channel)
        buffer.clear(channel, 0, buffer.getNumSamples());
    buffer.setSample(0, 0, 0.25f);
    buffer.setSample(1, 0, 0.25f);
    juce::MidiBuffer midi;
    instance->processBlock(buffer, midi);
    if (std::abs(buffer.getSample(0, 0) - 0.25f) > 0.0001f)
        return fail(6, "Empty VST3 did not preserve input audio.");

    const auto fixture = root.getChildFile("generated.wav");
    if (! writeTone(fixture))
        return fail(7, "Generated-audio host fixture could not be written.");
    loopgenerator::LoopGeneratorAudioProcessor stateSource;
    stateSource.prepareToPlay(48000.0, 512);
    if (stateSource.loadGeneratedAudio(fixture, 2, 120.0).failed())
        return fail(8, "Generated-audio host fixture could not be loaded.");
    juce::MemoryBlock generatedState;
    stateSource.getStateInformation(generatedState);
    juce::XmlElement vst3State("VST3PluginState");
    vst3State.createNewChildElement("IComponent")
        ->addTextElement(generatedState.toBase64Encoding());
    juce::MemoryBlock hostedState;
    juce::AudioProcessor::copyXmlToBinary(vst3State, hostedState);
    instance->setStateInformation(
        hostedState.getData(), static_cast<int>(hostedState.getSize()));
    TestPlayHead playHead;
    playHead.position.setIsPlaying(true);
    playHead.position.setBpm(120.0);
    playHead.position.setTimeSignature(
        juce::AudioPlayHead::TimeSignature { 4, 4 });
    playHead.position.setPpqPosition(0.0);
    instance->setPlayHead(&playHead);
    buffer.clear();
    instance->processBlock(buffer, midi);
    if (buffer.getRMSLevel(0, 0, buffer.getNumSamples()) <= 0.01f)
        return fail(9, "VST3 wrapper produced no host-synchronized generated audio.");

    std::cout << "VST3 discovered, instantiated, opened, persisted, passed through, "
                 "and emitted host-synchronized generated audio\n";
    return 0;
}
