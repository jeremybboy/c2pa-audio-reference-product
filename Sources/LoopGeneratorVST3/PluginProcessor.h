#pragma once

#include "GeneratedLoop.h"
#include "GenerationService.h"
#include "C2PASigningService.h"

#include <juce_audio_processors/juce_audio_processors.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <thread>

namespace loopgenerator
{
namespace parameter
{
inline constexpr auto gain = "gain";
inline constexpr auto loop = "loop";
inline constexpr auto sync = "sync";
inline constexpr auto bars = "bars";
}

class LoopGeneratorAudioProcessor final : public juce::AudioProcessor
{
public:
    LoopGeneratorAudioProcessor();
    ~LoopGeneratorAudioProcessor() override;

    void prepareToPlay(double sampleRate, int maximumExpectedSamplesPerBlock) override;
    void releaseResources() override;
    bool isBusesLayoutSupported(const BusesLayout& layouts) const override;
    void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }
    const juce::String getName() const override { return "Loop Generator"; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String&) override {}
    void getStateInformation(juce::MemoryBlock&) override;
    void setStateInformation(const void*, int) override;

    juce::AudioProcessorValueTreeState& parameters() noexcept { return apvts; }
    bool requestGeneration(
        const juce::String& instrument,
        const juce::String& prompt,
        std::int64_t seed);
    void cancelGeneration();
    bool isGenerating() const noexcept { return generating.load(std::memory_order_acquire); }
    juce::String statusText() const;
    juce::String promptText() const;
    juce::String instrumentText() const;
    std::int64_t seedValue() const;
    juce::File generatedFile() const;
    bool generatedHasContentCredentials() const;
    double generatedDurationSeconds() const;
    double currentHostBpm() const noexcept;
    int currentTimeSignatureNumerator() const noexcept;
    int currentTimeSignatureDenominator() const noexcept;
    int selectedBars() const noexcept;
    bool runtimeIsReady() const noexcept { return runtimeReady.load(std::memory_order_acquire); }
    void setPreviewPlaying(bool shouldPlay) noexcept;
    bool isPreviewPlaying() const noexcept;
    juce::Result loadGeneratedAudio(
        const juce::File& file,
        int bars,
        double generationBpm,
        bool contentCredentialsPresent = false);

    static juce::AudioProcessorValueTreeState::ParameterLayout createParameterLayout();

private:
    void updateTransport(const juce::Optional<juce::AudioPlayHead::PositionInfo>& position);
    void renderSynchronized(
        juce::AudioBuffer<float>& buffer,
        const GeneratedLoop& loopData,
        const juce::AudioPlayHead::PositionInfo& position);
    void renderPreview(juce::AudioBuffer<float>& buffer, const GeneratedLoop& loopData);
    void setStatus(const juce::String& status);

    juce::AudioProcessorValueTreeState apvts;
    GeneratedLoopStore loopStore;
    std::unique_ptr<StableAudioGenerationService> generationService;
    std::unique_ptr<C2PASigningService> signingService;
    std::thread generationThread;
    std::atomic<bool> generating { false };
    std::atomic<bool> runtimeReady { false };
    std::atomic<bool> previewPlaying { false };
    std::atomic<double> hostBpm { 120.0 };
    std::atomic<int> timeSignatureNumerator { 4 };
    std::atomic<int> timeSignatureDenominator { 4 };

    mutable std::mutex metadataMutex;
    juce::String status { "Checking Stable Audio runtime…" };
    juce::String prompt { "Warm analog pad, evolving, cinematic, uplifting" };
    juce::String instrument { "Synth" };
    std::int64_t seed { 424242 };
    juce::File currentGeneratedFile;
    bool currentGeneratedSigned { false };
    double currentGeneratedDuration { 0.0 };
    double currentGenerationBpm { 120.0 };

    double preparedSampleRate { 48000.0 };
    double previewSourcePosition { 0.0 };
    double syncOriginPpq { 0.0 };
    double lastPpqEnd { 0.0 };
    bool transportWasPlaying { false };
    bool previewWasPlaying { false };

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LoopGeneratorAudioProcessor)
};
}
