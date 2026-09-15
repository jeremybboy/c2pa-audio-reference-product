#include "PluginEditor.h"

#include <limits>

namespace loopgenerator
{
namespace
{
const auto background = juce::Colour(0xff0a0f18);
const auto panel = juce::Colour(0xff111925);
const auto border = juce::Colour(0xff293345);
const auto purple = juce::Colour(0xff8b5cf6);
const auto muted = juce::Colour(0xffa7afbd);
}

WaveformView::WaveformView()
{
    formats.registerBasicFormats();
}

void WaveformView::setFile(const juce::File& file)
{
    if (file == currentFile)
        return;
    currentFile = file;
    thumbnail.clear();
    if (file.existsAsFile())
        thumbnail.setSource(new juce::FileInputSource(file));
    repaint();
}

void WaveformView::paint(juce::Graphics& graphics)
{
    const auto area = getLocalBounds().toFloat();
    graphics.setColour(panel.brighter(0.05f));
    graphics.fillRoundedRectangle(area, 8.0f);
    graphics.setColour(border);
    graphics.drawRoundedRectangle(area.reduced(0.5f), 8.0f, 1.0f);
    if (thumbnail.getTotalLength() > 0.0)
    {
        graphics.setColour(purple);
        thumbnail.drawChannels(
            graphics,
            getLocalBounds().reduced(10),
            0.0,
            thumbnail.getTotalLength(),
            1.0f);
    }
    else
    {
        graphics.setColour(muted);
        graphics.setFont(14.0f);
        graphics.drawFittedText(
            "Generate a loop to see its waveform",
            getLocalBounds(),
            juce::Justification::centred,
            1);
    }
}

DragWavButton::DragWavButton(std::function<juce::File()> provider)
    : juce::TextButton("Drag WAV to DAW"), fileProvider(std::move(provider))
{
    setMouseCursor(juce::MouseCursor::DraggingHandCursor);
}

void DragWavButton::mouseDown(const juce::MouseEvent& event)
{
    dragStarted = false;
    juce::TextButton::mouseDown(event);
}

void DragWavButton::mouseDrag(const juce::MouseEvent& event)
{
    juce::TextButton::mouseDrag(event);
    const auto file = fileProvider();
    if (! dragStarted && event.getDistanceFromDragStart() > 5 && file.existsAsFile())
    {
        dragStarted = juce::DragAndDropContainer::performExternalDragDropOfFiles(
            juce::StringArray { file.getFullPathName() },
            false,
            this);
    }
}

LoopGeneratorAudioProcessorEditor::LoopGeneratorAudioProcessorEditor(
    LoopGeneratorAudioProcessor& owner)
    : juce::AudioProcessorEditor(owner),
      ownerProcessor(owner),
      dragButton([this] { return ownerProcessor.generatedFile(); })
{
    setSize(780, 620);
    setResizable(true, true);
    setResizeLimits(680, 540, 1100, 850);

    configureLabel(title, 28.0f, juce::Colours::white);
    title.setText("Loop Generator", juce::dontSendNotification);
    configureLabel(subtitle, 14.0f, muted);
    subtitle.setText(
        "Stable Audio Open Small • VST3 audio effect",
        juce::dontSendNotification);
    configureLabel(instrumentLabel, 13.0f, muted);
    instrumentLabel.setText("INSTRUMENT", juce::dontSendNotification);
    configureLabel(promptLabel, 13.0f, muted);
    promptLabel.setText("PROMPT", juce::dontSendNotification);
    configureLabel(barsLabel, 13.0f, muted);
    barsLabel.setText("LENGTH", juce::dontSendNotification);
    configureLabel(seedLabel, 13.0f, muted);
    seedLabel.setText("SEED", juce::dontSendNotification);
    configureLabel(gainLabel, 13.0f, muted);
    gainLabel.setText("OUTPUT", juce::dontSendNotification);
    configureLabel(hostLabel, 13.0f, muted);
    configureLabel(statusLabel, 14.0f, juce::Colours::white);
    statusLabel.setJustificationType(juce::Justification::centredLeft);
    configureLabel(fileLabel, 12.0f, muted);

    instrumentBox.addItemList(
        { "Synth", "Bass", "Drums", "Piano", "Guitar", "Strings", "FX" },
        1);
    instrumentBox.setText(ownerProcessor.instrumentText(), juce::dontSendNotification);
    barsBox.addItemList({ "1 bar", "2 bars", "4 bars" }, 1);
    promptEditor.setText(ownerProcessor.promptText(), false);
    promptEditor.setMultiLine(true, true);
    promptEditor.setReturnKeyStartsNewLine(true);
    promptEditor.setTextToShowWhenEmpty("Describe the loop…", muted);
    promptEditor.setInputRestrictions(200);
    seedEditor.setText(juce::String(ownerProcessor.seedValue()), false);
    seedEditor.setInputRestrictions(19, "0123456789");

    gainSlider.setSliderStyle(juce::Slider::LinearHorizontal);
    gainSlider.setTextBoxStyle(juce::Slider::TextBoxRight, false, 72, 24);
    gainSlider.setTextValueSuffix(" dB");

    auto& state = ownerProcessor.parameters();
    syncAttachment = std::make_unique<ButtonAttachment>(state, parameter::sync, syncButton);
    loopAttachment = std::make_unique<ButtonAttachment>(state, parameter::loop, loopButton);
    barsAttachment = std::make_unique<ComboBoxAttachment>(state, parameter::bars, barsBox);
    gainAttachment = std::make_unique<SliderAttachment>(state, parameter::gain, gainSlider);

    randomizeButton.onClick = [this]
    {
        const auto value = juce::Random::getSystemRandom().nextInt64()
            & std::numeric_limits<std::int64_t>::max();
        seedEditor.setText(juce::String(value), false);
    };
    generateButton.onClick = [this] { beginGeneration(); };
    previewButton.onClick = [this]
    {
        ownerProcessor.setPreviewPlaying(! ownerProcessor.isPreviewPlaying());
    };
    revealButton.onClick = [this]
    {
        const auto file = ownerProcessor.generatedFile();
        if (file.existsAsFile())
            file.revealToUser();
    };

    juce::Component* components[] {
        &title, &subtitle, &instrumentLabel, &promptLabel, &barsLabel, &seedLabel,
        &gainLabel, &hostLabel, &statusLabel, &fileLabel, &instrumentBox, &barsBox,
        &promptEditor, &seedEditor, &randomizeButton, &generateButton, &previewButton,
        &syncButton, &loopButton, &gainSlider, &dragButton, &revealButton, &waveform
    };
    for (auto* component : components)
        addAndMakeVisible(component);

    startTimerHz(10);
    timerCallback();
}

void LoopGeneratorAudioProcessorEditor::configureLabel(
    juce::Label& label,
    float size,
    juce::Colour colour)
{
    label.setFont(juce::FontOptions(size));
    label.setColour(juce::Label::textColourId, colour);
}

void LoopGeneratorAudioProcessorEditor::beginGeneration()
{
    auto requestedSeed = seedEditor.getText().getLargeIntValue();
    if (seedEditor.getText().trim().isEmpty())
    {
        requestedSeed = juce::Random::getSystemRandom().nextInt64()
            & std::numeric_limits<std::int64_t>::max();
        seedEditor.setText(juce::String(requestedSeed), false);
    }
    ownerProcessor.setPreviewPlaying(false);
    ownerProcessor.requestGeneration(
        instrumentBox.getText(),
        promptEditor.getText(),
        requestedSeed);
}

void LoopGeneratorAudioProcessorEditor::paint(juce::Graphics& graphics)
{
    graphics.fillAll(background);
    auto header = getLocalBounds().removeFromTop(82).toFloat();
    graphics.setColour(panel);
    graphics.fillRect(header);
    graphics.setColour(purple);
    graphics.fillRect(juce::Rectangle<float>(
        0.0f, 80.0f, static_cast<float>(getWidth()) * 0.42f, 2.0f));

    auto content = getLocalBounds().reduced(18).withTrimmedTop(74).toFloat();
    graphics.setColour(panel);
    graphics.fillRoundedRectangle(content, 10.0f);
    graphics.setColour(border);
    graphics.drawRoundedRectangle(content.reduced(0.5f), 10.0f, 1.0f);
}

void LoopGeneratorAudioProcessorEditor::resized()
{
    auto area = getLocalBounds().reduced(22);
    title.setBounds(area.removeFromTop(36));
    subtitle.setBounds(area.removeFromTop(24));
    area.removeFromTop(18);

    auto content = area.reduced(16);
    auto firstRow = content.removeFromTop(62);
    auto instrumentArea = firstRow.removeFromLeft(190);
    instrumentLabel.setBounds(instrumentArea.removeFromTop(20));
    instrumentBox.setBounds(instrumentArea.removeFromTop(34));
    firstRow.removeFromLeft(14);
    auto barsArea = firstRow.removeFromLeft(130);
    barsLabel.setBounds(barsArea.removeFromTop(20));
    barsBox.setBounds(barsArea.removeFromTop(34));
    firstRow.removeFromLeft(14);
    gainLabel.setBounds(firstRow.removeFromTop(20));
    gainSlider.setBounds(firstRow.removeFromTop(34));

    content.removeFromTop(10);
    promptLabel.setBounds(content.removeFromTop(20));
    promptEditor.setBounds(content.removeFromTop(82));
    content.removeFromTop(10);

    auto seedRow = content.removeFromTop(54);
    auto seedArea = seedRow.removeFromLeft(310);
    seedLabel.setBounds(seedArea.removeFromTop(20));
    auto seedControls = seedArea.removeFromTop(34);
    randomizeButton.setBounds(seedControls.removeFromRight(88));
    seedControls.removeFromRight(8);
    seedEditor.setBounds(seedControls);
    seedRow.removeFromLeft(14);
    syncButton.setBounds(seedRow.removeFromLeft(105));
    loopButton.setBounds(seedRow.removeFromLeft(80));
    generateButton.setBounds(seedRow.removeFromRight(180));

    content.removeFromTop(10);
    waveform.setBounds(content.removeFromTop(112));
    content.removeFromTop(8);
    hostLabel.setBounds(content.removeFromTop(22));
    statusLabel.setBounds(content.removeFromTop(28));
    fileLabel.setBounds(content.removeFromTop(22));

    auto bottom = content.removeFromBottom(38);
    previewButton.setBounds(bottom.removeFromLeft(100));
    bottom.removeFromLeft(8);
    dragButton.setBounds(bottom.removeFromLeft(160));
    bottom.removeFromLeft(8);
    revealButton.setBounds(bottom.removeFromLeft(110));
}

void LoopGeneratorAudioProcessorEditor::timerCallback()
{
    const auto bpm = ownerProcessor.currentHostBpm();
    const auto numerator = ownerProcessor.currentTimeSignatureNumerator();
    const auto denominator = ownerProcessor.currentTimeSignatureDenominator();
    const auto bars = ownerProcessor.selectedBars();
    const auto seconds = static_cast<double>(bars) * static_cast<double>(numerator)
        * 4.0 / static_cast<double>(juce::jmax(1, denominator)) * 60.0 / bpm;
    hostLabel.setText(
        "Host: " + juce::String(bpm, 1) + " BPM • "
            + juce::String(numerator) + "/" + juce::String(denominator)
            + " • generated length " + juce::String(seconds, 2) + " s",
        juce::dontSendNotification);
    statusLabel.setText(ownerProcessor.statusText(), juce::dontSendNotification);
    generateButton.setEnabled(! ownerProcessor.isGenerating());
    generateButton.setButtonText(
        ownerProcessor.isGenerating() ? "Generating…" : "Generate Loop");
    previewButton.setButtonText(
        ownerProcessor.isPreviewPlaying() ? "Stop Preview" : "Preview");

    const auto file = ownerProcessor.generatedFile();
    dragButton.setEnabled(file.existsAsFile());
    revealButton.setEnabled(file.existsAsFile());
    fileLabel.setText(
        file.existsAsFile()
            ? (ownerProcessor.generatedHasContentCredentials() ? "C2PA • " : "Unsigned • ")
                + file.getFileName()
            : "No generated WAV yet",
        juce::dontSendNotification);
    if (file != displayedFile)
    {
        displayedFile = file;
        waveform.setFile(file);
    }
}
}
