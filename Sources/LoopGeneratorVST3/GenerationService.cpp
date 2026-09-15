#include "GenerationService.h"

#include <cmath>

namespace loopgenerator
{
namespace
{
juce::File bundledInferenceScript()
{
    const auto executable = juce::File::getSpecialLocation(
        juce::File::currentExecutableFile);
    return executable.getParentDirectory()
        .getParentDirectory()
        .getChildFile("Resources/runtime/stable_audio/infer.py");
}

juce::String secondsArgument(double seconds)
{
    auto text = juce::String(seconds, 6).trimCharactersAtEnd("0");
    return text.endsWithChar('.') ? text.dropLastCharacters(1) : text;
}
}

juce::String GenerationRequest::finalPrompt() const
{
    return instrument.trim() + " loop, " + prompt.trim();
}

double GenerationRequest::durationSeconds() const
{
    if (bpm <= 0.0 || timeSignatureDenominator <= 0)
        return 0.0;
    const auto quarterNotesPerBar = static_cast<double>(timeSignatureNumerator)
        * 4.0 / static_cast<double>(timeSignatureDenominator);
    return static_cast<double>(bars) * quarterNotesPerBar * 60.0 / bpm;
}

juce::Result GenerationRequest::validate() const
{
    const auto cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty())
        return juce::Result::fail("Enter a prompt before generating.");
    if (cleanPrompt.length() > 200)
        return juce::Result::fail("Keep the prompt to 200 characters or fewer.");
    if (instrument.trim().isEmpty())
        return juce::Result::fail("Choose an instrument family.");
    if (bars != 1 && bars != 2 && bars != 4)
        return juce::Result::fail("Loop length must be 1, 2, or 4 bars.");
    if (! std::isfinite(bpm) || bpm < 20.0 || bpm > 400.0)
        return juce::Result::fail("Host tempo is outside the supported range.");
    if (timeSignatureNumerator <= 0 || timeSignatureDenominator <= 0)
        return juce::Result::fail("Host time signature is unavailable.");
    const auto seconds = durationSeconds();
    if (seconds < 1.0 || seconds > 11.0)
        return juce::Result::fail(
            "This bar length is " + juce::String(seconds, 2)
            + " seconds at the host tempo; Stable Audio supports 1 to 11 seconds.");
    return juce::Result::ok();
}

juce::Result RuntimeConfiguration::validate() const
{
    if (! pythonExecutable.existsAsFile())
        return juce::Result::fail("Stable Audio Python runtime is missing.");
    if (! inferenceScript.existsAsFile())
        return juce::Result::fail("Stable Audio inference helper is missing.");
    if (! modelCache.isDirectory())
        return juce::Result::fail("Stable Audio model cache is missing.");
    return juce::Result::ok();
}

std::optional<RuntimeConfiguration> RuntimeConfiguration::discover(juce::String& error)
{
    const auto explicitPython = juce::SystemStats::getEnvironmentVariable(
        "LOOP_GENERATOR_PYTHON", {});
    const auto explicitScript = juce::SystemStats::getEnvironmentVariable(
        "LOOP_GENERATOR_RUNTIME_SCRIPT", {});
    const auto explicitCache = juce::SystemStats::getEnvironmentVariable(
        "LOOP_GENERATOR_MODEL_CACHE", {});
    if (explicitPython.isNotEmpty() && explicitScript.isNotEmpty()
        && explicitCache.isNotEmpty())
    {
        RuntimeConfiguration configuration {
            juce::File(explicitPython), juce::File(explicitScript), juce::File(explicitCache)
        };
        if (auto result = configuration.validate(); result.wasOk())
            return configuration;
        else
            error = result.getErrorMessage();
    }

    const auto runtimeDirectory = juce::File::getSpecialLocation(
        juce::File::userApplicationDataDirectory)
        .getChildFile("Application Support/LoopGenerator/runtime");
    auto script = bundledInferenceScript();
    if (! script.existsAsFile())
        script = runtimeDirectory.getChildFile("infer.py");
    RuntimeConfiguration installed {
        runtimeDirectory.getChildFile(".venv/bin/python"),
        script,
        runtimeDirectory.getChildFile(".model-cache")
    };
    if (auto result = installed.validate(); result.wasOk())
        return installed;
    else
        error = result.getErrorMessage()
            + " Run scripts/install_vst3.sh from the Loop Generator repository.";
    return std::nullopt;
}

StableAudioGenerationService::StableAudioGenerationService(
    RuntimeConfiguration configuration)
    : runtime(std::move(configuration))
{
}

StableAudioGenerationService::~StableAudioGenerationService()
{
    cancel();
}

juce::File StableAudioGenerationService::generatedAudioDirectory()
{
    return juce::File::getSpecialLocation(juce::File::userApplicationDataDirectory)
        .getChildFile("Caches/LoopGenerator/generated");
}

juce::StringArray StableAudioGenerationService::commandArguments(
    const RuntimeConfiguration& configuration,
    const GenerationRequest& request,
    const juce::File& audioFile,
    const juce::File& metadataFile)
{
    return {
        "/usr/bin/env",
        "PYTHONUNBUFFERED=1",
        "HF_HUB_DISABLE_PROGRESS_BARS=1",
        "TOKENIZERS_PARALLELISM=false",
        "HF_HUB_OFFLINE=1",
        "TRANSFORMERS_OFFLINE=1",
        "HF_HUB_CACHE=" + configuration.modelCache.getFullPathName(),
        configuration.pythonExecutable.getFullPathName(),
        configuration.inferenceScript.getFullPathName(),
        "--prompt", request.finalPrompt(),
        "--seconds", secondsArgument(request.durationSeconds()),
        "--seed", juce::String(request.seed),
        "--output", audioFile.getFullPathName(),
        "--metadata-output", metadataFile.getFullPathName()
    };
}

GenerationOutcome StableAudioGenerationService::generate(
    const GenerationRequest& request,
    const std::function<void(const juce::String&)>& statusCallback)
{
    if (auto result = request.validate(); result.failed())
        return { false, result.getErrorMessage(), {} };
    if (auto result = runtime.validate(); result.failed())
        return { false, result.getErrorMessage(), {} };

    cancellationRequested.store(false, std::memory_order_release);
    auto outputDirectory = generatedAudioDirectory();
    if (outputDirectory.createDirectory().failed())
        return { false, "Could not create the generated-loop cache.", {} };

    const auto stem = "loop-" + juce::Uuid().toString();
    const auto audioFile = outputDirectory.getChildFile(stem + ".wav");
    const auto metadataFile = outputDirectory.getChildFile(stem + ".model.json");
    juce::ChildProcess process;
    {
        const std::scoped_lock lock(processMutex);
        activeProcess = &process;
    }
    const auto clearActiveProcess = [this]
    {
        const std::scoped_lock lock(processMutex);
        activeProcess = nullptr;
    };

    if (statusCallback)
        statusCallback("Loading Stable Audio and generating…");
    if (! process.start(commandArguments(runtime, request, audioFile, metadataFile)))
    {
        clearActiveProcess();
        return { false, "Could not start the Stable Audio runtime.", {} };
    }

    process.waitForProcessToFinish(-1);
    if (cancellationRequested.load(std::memory_order_acquire))
    {
        clearActiveProcess();
        audioFile.deleteFile();
        metadataFile.deleteFile();
        return { false, "Generation cancelled.", {} };
    }

    const auto output = process.readAllProcessOutput().trim();
    const auto exitCode = process.getExitCode();
    clearActiveProcess();
    if (exitCode != 0 || ! audioFile.existsAsFile())
    {
        audioFile.deleteFile();
        metadataFile.deleteFile();
        return {
            false,
            output.isNotEmpty() ? output.substring(0, 1000)
                                : "Stable Audio generation failed.",
            {}
        };
    }

    return {
        true,
        {},
        {
            audioFile,
            metadataFile,
            request.durationSeconds(),
            request.bpm,
            request.bars,
            request.seed
        }
    };
}

void StableAudioGenerationService::cancel()
{
    cancellationRequested.store(true, std::memory_order_release);
    const std::scoped_lock lock(processMutex);
    if (activeProcess != nullptr && activeProcess->isRunning())
        activeProcess->kill();
}
}
