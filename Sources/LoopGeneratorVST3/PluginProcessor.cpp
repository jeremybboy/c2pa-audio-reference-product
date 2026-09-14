#include "PluginProcessor.h"
#include "PluginEditor.h"

#include <cmath>

namespace loopgenerator
{
namespace
{
int barsFromChoice(float choice)
{
    constexpr int values[] { 1, 2, 4 };
    return values[juce::jlimit(0, 2, juce::roundToInt(choice))];
}

float interpolatedSample(const GeneratedLoop& loopData, int channel, double position)
{
    const auto frames = loopData.audio.getNumSamples();
    if (frames <= 0)
        return 0.0f;
    const auto wrapped = juce::jlimit(0.0, static_cast<double>(frames - 1), position);
    const auto first = juce::jlimit(0, frames - 1, static_cast<int>(wrapped));
    const auto second = juce::jmin(first + 1, frames - 1);
    const auto fraction = static_cast<float>(wrapped - static_cast<double>(first));
    const auto sourceChannel = juce::jmin(channel, loopData.audio.getNumChannels() - 1);
    const auto a = loopData.audio.getSample(sourceChannel, first);
    const auto b = loopData.audio.getSample(sourceChannel, second);
    return a + fraction * (b - a);
}
}

LoopGeneratorAudioProcessor::LoopGeneratorAudioProcessor()
    : AudioProcessor(BusesProperties()
        .withInput("Input", juce::AudioChannelSet::stereo(), true)
        .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      apvts(*this, nullptr, "LOOP_GENERATOR_STATE", createParameterLayout())
{
    juce::String error;
    if (auto discovered = RuntimeConfiguration::discover(error))
    {
        generationService = std::make_unique<StableAudioGenerationService>(*discovered);
        runtimeReady.store(true, std::memory_order_release);
        status = "Ready — host sync is enabled.";
    }
    else
    {
        status = error;
    }
}

LoopGeneratorAudioProcessor::~LoopGeneratorAudioProcessor()
{
    cancelGeneration();
    if (generationThread.joinable())
        generationThread.join();
}

juce::AudioProcessorValueTreeState::ParameterLayout
LoopGeneratorAudioProcessor::createParameterLayout()
{
    std::vector<std::unique_ptr<juce::RangedAudioParameter>> parameters;
    parameters.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID { parameter::gain, 1 },
        "Output Gain",
        juce::NormalisableRange<float> { -60.0f, 6.0f, 0.1f },
        0.0f));
    parameters.push_back(std::make_unique<juce::AudioParameterBool>(
        juce::ParameterID { parameter::loop, 1 }, "Loop", true));
    parameters.push_back(std::make_unique<juce::AudioParameterBool>(
        juce::ParameterID { parameter::sync, 1 }, "Host Sync", true));
    parameters.push_back(std::make_unique<juce::AudioParameterChoice>(
        juce::ParameterID { parameter::bars, 1 },
        "Bars",
        juce::StringArray { "1", "2", "4" },
        1));
    return { parameters.begin(), parameters.end() };
}

void LoopGeneratorAudioProcessor::prepareToPlay(double sampleRate, int)
{
    preparedSampleRate = sampleRate > 0.0 ? sampleRate : 48000.0;
    previewSourcePosition = 0.0;
    syncOriginPpq = 0.0;
    lastPpqEnd = 0.0;
    transportWasPlaying = false;
    previewWasPlaying = false;
}

void LoopGeneratorAudioProcessor::releaseResources()
{
}

bool LoopGeneratorAudioProcessor::isBusesLayoutSupported(const BusesLayout& layouts) const
{
    const auto output = layouts.getMainOutputChannelSet();
    return (output == juce::AudioChannelSet::mono()
            || output == juce::AudioChannelSet::stereo())
        && layouts.getMainInputChannelSet() == output;
}

void LoopGeneratorAudioProcessor::processBlock(
    juce::AudioBuffer<float>& buffer,
    juce::MidiBuffer&)
{
    juce::ScopedNoDenormals noDenormals;
    juce::Optional<juce::AudioPlayHead::PositionInfo> position;
    if (auto* playHead = getPlayHead())
        position = playHead->getPosition();
    updateTransport(position);

    const auto loopData = loopStore.snapshot();
    if (loopData == nullptr)
        return;

    buffer.clear();
    const auto syncEnabled = apvts.getRawParameterValue(parameter::sync)
        ->load(std::memory_order_relaxed) >= 0.5f;
    if (syncEnabled)
    {
        if (position && position->getIsPlaying())
        {
            previewWasPlaying = false;
            renderSynchronized(buffer, *loopData, *position);
            return;
        }
        transportWasPlaying = false;
    }
    if (previewPlaying.load(std::memory_order_acquire))
    {
        if (! previewWasPlaying)
            previewSourcePosition = 0.0;
        previewWasPlaying = true;
        renderPreview(buffer, *loopData);
    }
    else
    {
        previewWasPlaying = false;
    }
}

void LoopGeneratorAudioProcessor::updateTransport(
    const juce::Optional<juce::AudioPlayHead::PositionInfo>& position)
{
    if (! position)
        return;
    if (const auto bpm = position->getBpm(); bpm && *bpm > 0.0)
        hostBpm.store(*bpm, std::memory_order_release);
    if (const auto signature = position->getTimeSignature())
    {
        timeSignatureNumerator.store(signature->numerator, std::memory_order_release);
        timeSignatureDenominator.store(signature->denominator, std::memory_order_release);
    }
}

void LoopGeneratorAudioProcessor::renderSynchronized(
    juce::AudioBuffer<float>& buffer,
    const GeneratedLoop& loopData,
    const juce::AudioPlayHead::PositionInfo& position)
{
    const auto bpm = position.getBpm().orFallback(currentHostBpm());
    const auto signature = position.getTimeSignature().orFallback(
        juce::AudioPlayHead::TimeSignature {
            currentTimeSignatureNumerator(), currentTimeSignatureDenominator()
        });
    const auto beatsPerBar = static_cast<double>(signature.numerator)
        * 4.0 / static_cast<double>(juce::jmax(1, signature.denominator));
    const auto loopBeats = static_cast<double>(loopData.bars) * beatsPerBar;
    const auto beatsPerSample = bpm / (60.0 * preparedSampleRate);
    auto ppqStart = position.getPpqPosition().orFallback(0.0);
    if (! position.getPpqPosition())
        if (const auto time = position.getTimeInSamples())
            ppqStart = static_cast<double>(*time) * beatsPerSample;

    if (! transportWasPlaying || std::abs(ppqStart - lastPpqEnd) > 0.25)
        syncOriginPpq = ppqStart;
    transportWasPlaying = true;
    lastPpqEnd = ppqStart + beatsPerSample * static_cast<double>(buffer.getNumSamples());

    const auto shouldLoop = apvts.getRawParameterValue(parameter::loop)
        ->load(std::memory_order_relaxed) >= 0.5f;
    const auto gain = juce::Decibels::decibelsToGain(
        apvts.getRawParameterValue(parameter::gain)->load(std::memory_order_relaxed));
    for (int sample = 0; sample < buffer.getNumSamples(); ++sample)
    {
        auto relativeBeats = ppqStart + beatsPerSample * static_cast<double>(sample)
            - syncOriginPpq;
        if (! shouldLoop && (relativeBeats < 0.0 || relativeBeats >= loopBeats))
            continue;
        relativeBeats = std::fmod(relativeBeats, loopBeats);
        if (relativeBeats < 0.0)
            relativeBeats += loopBeats;
        const auto sourcePosition = relativeBeats / loopBeats
            * static_cast<double>(loopData.audio.getNumSamples() - 1);
        for (int channel = 0; channel < buffer.getNumChannels(); ++channel)
            buffer.setSample(
                channel,
                sample,
                gain * interpolatedSample(loopData, channel, sourcePosition));
    }
}

void LoopGeneratorAudioProcessor::renderPreview(
    juce::AudioBuffer<float>& buffer,
    const GeneratedLoop& loopData)
{
    const auto step = loopData.sampleRate / preparedSampleRate;
    const auto shouldLoop = apvts.getRawParameterValue(parameter::loop)
        ->load(std::memory_order_relaxed) >= 0.5f;
    const auto gain = juce::Decibels::decibelsToGain(
        apvts.getRawParameterValue(parameter::gain)->load(std::memory_order_relaxed));
    for (int sample = 0; sample < buffer.getNumSamples(); ++sample)
    {
        if (previewSourcePosition >= loopData.audio.getNumSamples())
        {
            if (! shouldLoop)
            {
                previewPlaying.store(false, std::memory_order_release);
                break;
            }
            previewSourcePosition = std::fmod(
                previewSourcePosition,
                static_cast<double>(loopData.audio.getNumSamples()));
        }
        for (int channel = 0; channel < buffer.getNumChannels(); ++channel)
            buffer.setSample(
                channel,
                sample,
                gain * interpolatedSample(loopData, channel, previewSourcePosition));
        previewSourcePosition += step;
    }
}

bool LoopGeneratorAudioProcessor::requestGeneration(
    const juce::String& requestedInstrument,
    const juce::String& requestedPrompt,
    std::int64_t requestedSeed)
{
    bool expected = false;
    if (! generating.compare_exchange_strong(expected, true, std::memory_order_acq_rel))
        return false;
    if (generationThread.joinable())
        generationThread.join();

    if (generationService == nullptr)
    {
        juce::String error;
        if (auto discovered = RuntimeConfiguration::discover(error))
        {
            generationService = std::make_unique<StableAudioGenerationService>(*discovered);
            runtimeReady.store(true, std::memory_order_release);
        }
        else
        {
            setStatus(error);
            generating.store(false, std::memory_order_release);
            return false;
        }
    }

    GenerationRequest request;
    request.instrument = requestedInstrument;
    request.prompt = requestedPrompt;
    request.bars = selectedBars();
    request.seed = requestedSeed;
    request.bpm = currentHostBpm();
    request.timeSignatureNumerator = currentTimeSignatureNumerator();
    request.timeSignatureDenominator = currentTimeSignatureDenominator();
    if (auto result = request.validate(); result.failed())
    {
        setStatus(result.getErrorMessage());
        generating.store(false, std::memory_order_release);
        return false;
    }

    {
        const std::scoped_lock lock(metadataMutex);
        instrument = request.instrument;
        prompt = request.prompt;
        seed = request.seed;
        status = "Generation queued…";
    }
    generationThread = std::thread([this, request]
    {
        const auto outcome = generationService->generate(request, [this](const auto& message)
        {
            setStatus(message);
        });
        if (! outcome.succeeded)
        {
            setStatus(outcome.error);
            generating.store(false, std::memory_order_release);
            return;
        }
        if (auto result = loadGeneratedAudio(
                outcome.asset.audioFile,
                outcome.asset.bars,
                outcome.asset.generationBpm);
            result.failed())
        {
            setStatus(result.getErrorMessage());
            generating.store(false, std::memory_order_release);
            return;
        }
        {
            const std::scoped_lock lock(metadataMutex);
            currentGeneratedDuration = outcome.asset.durationSeconds;
            status = "Ready — press host Play or drag the WAV into the DAW.";
        }
        generating.store(false, std::memory_order_release);
    });
    return true;
}

void LoopGeneratorAudioProcessor::cancelGeneration()
{
    if (generationService != nullptr)
        generationService->cancel();
}

void LoopGeneratorAudioProcessor::setStatus(const juce::String& newStatus)
{
    const std::scoped_lock lock(metadataMutex);
    status = newStatus;
}

juce::String LoopGeneratorAudioProcessor::statusText() const
{
    const std::scoped_lock lock(metadataMutex);
    return status;
}

juce::String LoopGeneratorAudioProcessor::promptText() const
{
    const std::scoped_lock lock(metadataMutex);
    return prompt;
}

juce::String LoopGeneratorAudioProcessor::instrumentText() const
{
    const std::scoped_lock lock(metadataMutex);
    return instrument;
}

std::int64_t LoopGeneratorAudioProcessor::seedValue() const
{
    const std::scoped_lock lock(metadataMutex);
    return seed;
}

juce::File LoopGeneratorAudioProcessor::generatedFile() const
{
    const std::scoped_lock lock(metadataMutex);
    return currentGeneratedFile;
}

double LoopGeneratorAudioProcessor::generatedDurationSeconds() const
{
    const std::scoped_lock lock(metadataMutex);
    return currentGeneratedDuration;
}

double LoopGeneratorAudioProcessor::currentHostBpm() const noexcept
{
    return hostBpm.load(std::memory_order_acquire);
}

int LoopGeneratorAudioProcessor::currentTimeSignatureNumerator() const noexcept
{
    return timeSignatureNumerator.load(std::memory_order_acquire);
}

int LoopGeneratorAudioProcessor::currentTimeSignatureDenominator() const noexcept
{
    return timeSignatureDenominator.load(std::memory_order_acquire);
}

int LoopGeneratorAudioProcessor::selectedBars() const noexcept
{
    return barsFromChoice(
        apvts.getRawParameterValue(parameter::bars)->load(std::memory_order_relaxed));
}

void LoopGeneratorAudioProcessor::setPreviewPlaying(bool shouldPlay) noexcept
{
    previewPlaying.store(shouldPlay, std::memory_order_release);
}

bool LoopGeneratorAudioProcessor::isPreviewPlaying() const noexcept
{
    return previewPlaying.load(std::memory_order_acquire);
}

juce::Result LoopGeneratorAudioProcessor::loadGeneratedAudio(
    const juce::File& file,
    int bars,
    double generationBpm)
{
    if (auto result = loopStore.load(file, bars, generationBpm); result.failed())
        return result;
    const auto loaded = loopStore.snapshot();
    {
        const std::scoped_lock lock(metadataMutex);
        currentGeneratedFile = file;
        currentGenerationBpm = generationBpm;
        currentGeneratedDuration = loaded != nullptr
            ? static_cast<double>(loaded->audio.getNumSamples()) / loaded->sampleRate
            : 0.0;
    }
    previewSourcePosition = 0.0;
    return juce::Result::ok();
}

void LoopGeneratorAudioProcessor::getStateInformation(juce::MemoryBlock& destination)
{
    auto state = apvts.copyState();
    {
        const std::scoped_lock lock(metadataMutex);
        state.setProperty("prompt", prompt, nullptr);
        state.setProperty("instrument", instrument, nullptr);
        state.setProperty("seed", juce::String(seed), nullptr);
        state.setProperty("generatedFile", currentGeneratedFile.getFullPathName(), nullptr);
        state.setProperty("generatedDuration", currentGeneratedDuration, nullptr);
        state.setProperty("generationBpm", currentGenerationBpm, nullptr);
    }
    if (const auto xml = state.createXml())
        copyXmlToBinary(*xml, destination);
}

void LoopGeneratorAudioProcessor::setStateInformation(const void* data, int size)
{
    const auto xml = getXmlFromBinary(data, size);
    if (xml == nullptr || ! xml->hasTagName(apvts.state.getType()))
        return;
    auto state = juce::ValueTree::fromXml(*xml);
    const auto restoredPrompt = state.getProperty("prompt", prompt).toString();
    const auto restoredInstrument = state.getProperty("instrument", instrument).toString();
    const auto restoredSeed = state.getProperty("seed", juce::String(seed)).toString()
        .getLargeIntValue();
    const auto restoredFile = juce::File(
        state.getProperty("generatedFile").toString());
    const auto restoredBpm = static_cast<double>(state.getProperty("generationBpm", 120.0));
    apvts.replaceState(state);
    {
        const std::scoped_lock lock(metadataMutex);
        prompt = restoredPrompt;
        instrument = restoredInstrument;
        seed = restoredSeed;
    }
    if (restoredFile.existsAsFile())
    {
        if (auto result = loadGeneratedAudio(restoredFile, selectedBars(), restoredBpm);
            result.failed())
            setStatus("Saved loop is unavailable: " + result.getErrorMessage());
        else
            setStatus("Saved loop restored.");
    }
}

juce::AudioProcessorEditor* LoopGeneratorAudioProcessor::createEditor()
{
    return new LoopGeneratorAudioProcessorEditor(*this);
}
}

#if ! defined(LOOP_GENERATOR_NO_PLUGIN_ENTRY)
juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new loopgenerator::LoopGeneratorAudioProcessor();
}
#endif
