#pragma once

#include <juce_audio_formats/juce_audio_formats.h>

#include <memory>

namespace loopgenerator
{
struct GeneratedLoop
{
    juce::AudioBuffer<float> audio;
    double sampleRate { 44100.0 };
    int bars { 2 };
    double generationBpm { 120.0 };
    juce::File sourceFile;
};

class GeneratedLoopStore
{
public:
    juce::Result load(const juce::File& file, int bars, double generationBpm);
    std::shared_ptr<const GeneratedLoop> snapshot() const noexcept;
    void clear() noexcept;

private:
    std::shared_ptr<const GeneratedLoop> current;
};
}
