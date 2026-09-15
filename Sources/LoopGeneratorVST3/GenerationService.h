#pragma once

#include <juce_core/juce_core.h>

#include <atomic>
#include <functional>
#include <mutex>
#include <optional>

namespace loopgenerator
{
struct GenerationRequest
{
    juce::String instrument { "Synth" };
    juce::String prompt;
    int bars { 2 };
    std::int64_t seed { 0 };
    double bpm { 120.0 };
    int timeSignatureNumerator { 4 };
    int timeSignatureDenominator { 4 };

    juce::String finalPrompt() const;
    double durationSeconds() const;
    juce::Result validate() const;
};

struct GeneratedAsset
{
    juce::File audioFile;
    juce::File metadataFile;
    double durationSeconds { 0.0 };
    double generationBpm { 120.0 };
    int bars { 2 };
    std::int64_t seed { 0 };
};

struct GenerationOutcome
{
    bool succeeded { false };
    juce::String error;
    GeneratedAsset asset;
};

struct RuntimeConfiguration
{
    juce::File pythonExecutable;
    juce::File inferenceScript;
    juce::File modelCache;

    juce::Result validate() const;
    static std::optional<RuntimeConfiguration> discover(juce::String& error);
};

class StableAudioGenerationService
{
public:
    explicit StableAudioGenerationService(RuntimeConfiguration configuration);
    ~StableAudioGenerationService();

    GenerationOutcome generate(
        const GenerationRequest& request,
        const std::function<void(const juce::String&)>& statusCallback = {});
    void cancel();

    static juce::File generatedAudioDirectory();
    static juce::StringArray commandArguments(
        const RuntimeConfiguration& configuration,
        const GenerationRequest& request,
        const juce::File& audioFile,
        const juce::File& metadataFile);

private:
    RuntimeConfiguration runtime;
    std::atomic<bool> cancellationRequested { false };
    std::mutex processMutex;
    juce::ChildProcess* activeProcess { nullptr };

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(StableAudioGenerationService)
};
}
