#pragma once

#include "PluginProcessor.h"

#include <juce_audio_utils/juce_audio_utils.h>
#include <juce_gui_extra/juce_gui_extra.h>

#include <functional>

namespace loopgenerator
{
class WaveformView final : public juce::Component
{
public:
    WaveformView();
    void setFile(const juce::File& file);
    void paint(juce::Graphics&) override;

private:
    juce::AudioFormatManager formats;
    juce::AudioThumbnailCache cache { 4 };
    juce::AudioThumbnail thumbnail { 512, formats, cache };
    juce::File currentFile;
};

class DragWavButton final : public juce::TextButton
{
public:
    explicit DragWavButton(std::function<juce::File()> provider);
    void mouseDown(const juce::MouseEvent&) override;
    void mouseDrag(const juce::MouseEvent&) override;

private:
    std::function<juce::File()> fileProvider;
    bool dragStarted { false };
};

class LoopGeneratorAudioProcessorEditor final
    : public juce::AudioProcessorEditor,
      private juce::Timer
{
public:
    explicit LoopGeneratorAudioProcessorEditor(LoopGeneratorAudioProcessor&);
    ~LoopGeneratorAudioProcessorEditor() override = default;

    void paint(juce::Graphics&) override;
    void resized() override;

private:
    void timerCallback() override;
    void beginGeneration();
    void configureLabel(juce::Label&, float size, juce::Colour colour);

    LoopGeneratorAudioProcessor& ownerProcessor;
    juce::Label title;
    juce::Label subtitle;
    juce::Label instrumentLabel;
    juce::Label promptLabel;
    juce::Label barsLabel;
    juce::Label seedLabel;
    juce::Label gainLabel;
    juce::Label hostLabel;
    juce::Label statusLabel;
    juce::Label fileLabel;
    juce::ComboBox instrumentBox;
    juce::ComboBox barsBox;
    juce::TextEditor promptEditor;
    juce::TextEditor seedEditor;
    juce::TextButton randomizeButton { "Random" };
    juce::TextButton generateButton { "Generate Loop" };
    juce::TextButton previewButton { "Preview" };
    juce::ToggleButton syncButton { "Host Sync" };
    juce::ToggleButton loopButton { "Loop" };
    juce::Slider gainSlider;
    DragWavButton dragButton;
    juce::TextButton revealButton { "Reveal WAV" };
    WaveformView waveform;

    using ButtonAttachment = juce::AudioProcessorValueTreeState::ButtonAttachment;
    using ComboBoxAttachment = juce::AudioProcessorValueTreeState::ComboBoxAttachment;
    using SliderAttachment = juce::AudioProcessorValueTreeState::SliderAttachment;
    std::unique_ptr<ButtonAttachment> syncAttachment;
    std::unique_ptr<ButtonAttachment> loopAttachment;
    std::unique_ptr<ComboBoxAttachment> barsAttachment;
    std::unique_ptr<SliderAttachment> gainAttachment;
    juce::File displayedFile;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LoopGeneratorAudioProcessorEditor)
};
}
