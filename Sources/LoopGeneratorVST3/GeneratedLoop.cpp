#include "GeneratedLoop.h"

#include <limits>

namespace loopgenerator
{
juce::Result GeneratedLoopStore::load(
    const juce::File& file,
    int bars,
    double generationBpm)
{
    juce::AudioFormatManager formats;
    formats.registerBasicFormats();
    auto reader = std::unique_ptr<juce::AudioFormatReader>(formats.createReaderFor(file));
    if (reader == nullptr)
        return juce::Result::fail("Generated WAV could not be opened.");
    if (reader->lengthInSamples <= 0
        || reader->lengthInSamples > std::numeric_limits<int>::max())
        return juce::Result::fail("Generated WAV has an unsupported length.");

    auto loaded = std::make_shared<GeneratedLoop>();
    loaded->audio.setSize(
        juce::jlimit(1, 2, static_cast<int>(reader->numChannels)),
        static_cast<int>(reader->lengthInSamples));
    if (! reader->read(
            &loaded->audio,
            0,
            loaded->audio.getNumSamples(),
            0,
            true,
            true))
        return juce::Result::fail("Generated WAV data could not be decoded.");

    loaded->sampleRate = reader->sampleRate;
    loaded->bars = juce::jlimit(1, 4, bars);
    loaded->generationBpm = generationBpm;
    loaded->sourceFile = file;
    std::atomic_store_explicit(
        &current,
        std::shared_ptr<const GeneratedLoop>(std::move(loaded)),
        std::memory_order_release);
    return juce::Result::ok();
}

std::shared_ptr<const GeneratedLoop> GeneratedLoopStore::snapshot() const noexcept
{
    return std::atomic_load_explicit(&current, std::memory_order_acquire);
}

void GeneratedLoopStore::clear() noexcept
{
    std::atomic_store_explicit(
        &current,
        std::shared_ptr<const GeneratedLoop> {},
        std::memory_order_release);
}
}
