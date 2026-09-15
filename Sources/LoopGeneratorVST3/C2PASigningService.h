#pragma once

#include <juce_core/juce_core.h>

#include <functional>
#include <optional>

namespace loopgenerator
{
struct C2PASigningConfiguration
{
    juce::File tool;
    juce::File signingBundle;
    juce::File trustAnchors;
    juce::File trustConfig;

    juce::Result validate() const;
    static std::optional<C2PASigningConfiguration> discover(juce::String& error);
};

struct C2PAToolResult
{
    int exitCode { -1 };
    juce::String output;
};

class C2PASigningService
{
public:
    using ToolRunner = std::function<C2PAToolResult(const juce::StringArray&)>;

    explicit C2PASigningService(
        C2PASigningConfiguration configuration,
        ToolRunner toolRunner = {});

    juce::Result signAndValidate(
        const juce::File& audioFile,
        const juce::File& modelMetadataFile) const;

    static juce::String manifestDefinition(
        const C2PASigningConfiguration& configuration,
        const juce::String& modelName,
        const juce::String& modelVersion);
    static bool validationReportIsTrusted(const juce::String& report);

private:
    static C2PAToolResult runTool(const juce::StringArray& arguments);

    C2PASigningConfiguration runtime;
    ToolRunner runner;
};
}
