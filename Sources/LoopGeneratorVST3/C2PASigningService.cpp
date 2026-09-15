#include "C2PASigningService.h"

#include <set>

namespace loopgenerator
{
namespace
{
constexpr auto signingCertificateFingerprint =
    "b27c27d45019dc80d4755a26207b9e02e236e54d70928573d68e4ece18068755";

juce::File applicationSupportC2PA()
{
    return juce::File::getSpecialLocation(juce::File::userApplicationDataDirectory)
        .getChildFile("Application Support/LoopGenerator/c2pa");
}

juce::File downloadsSigningBundle()
{
    return juce::File::getSpecialLocation(juce::File::userHomeDirectory)
        .getChildFile("Downloads/test-signing-bundle.pem");
}

std::set<juce::String> statusCodes(const juce::var& value)
{
    std::set<juce::String> result;
    if (const auto* entries = value.getArray())
        for (const auto& entry : *entries)
            if (const auto* object = entry.getDynamicObject())
                result.insert(object->getProperty("code").toString());
    return result;
}

bool containsPrivateKey(const juce::File& file)
{
    const auto pem = file.loadFileAsString();
    return pem.contains("-----BEGIN EC PRIVATE KEY-----")
        || pem.contains("-----BEGIN PRIVATE KEY-----");
}

juce::String certificateFingerprint(const juce::File& pem)
{
    juce::ChildProcess process;
    const juce::StringArray arguments {
        "/usr/bin/openssl", "x509", "-in", pem.getFullPathName(),
        "-noout", "-fingerprint", "-sha256"
    };
    if (! process.start(arguments))
        return {};
    process.waitForProcessToFinish(10000);
    const auto output = process.readAllProcessOutput().trim();
    return output.fromFirstOccurrenceOf("=", false, false)
        .removeCharacters(":").toLowerCase();
}

juce::DynamicObject::Ptr softwareAgent(
    const juce::String& name,
    const juce::String& version)
{
    auto result = juce::DynamicObject::Ptr(new juce::DynamicObject());
    result->setProperty("name", name);
    result->setProperty("version", version);
    return result;
}
}

juce::Result C2PASigningConfiguration::validate() const
{
    if (! tool.existsAsFile())
        return juce::Result::fail("c2patool is unavailable; run scripts/setup_c2pa.sh.");
    if (! signingBundle.existsAsFile() || ! containsPrivateKey(signingBundle))
        return juce::Result::fail(
            "The external C2PA test signing bundle is unavailable or has no private key.");
    if (certificateFingerprint(signingBundle) != signingCertificateFingerprint)
        return juce::Result::fail(
            "The external PEM is not the expected C2PA Conformance Test credential.");
    if (! trustAnchors.existsAsFile() || ! trustConfig.existsAsFile())
        return juce::Result::fail("C2PA test trust files are unavailable.");
    return juce::Result::ok();
}

std::optional<C2PASigningConfiguration> C2PASigningConfiguration::discover(
    juce::String& error)
{
    const auto support = applicationSupportC2PA();
    const auto explicitTool = juce::SystemStats::getEnvironmentVariable(
        "LOOP_GENERATOR_C2PATOOL", {});
    const auto explicitBundle = juce::SystemStats::getEnvironmentVariable(
        "LOOP_GENERATOR_C2PA_SIGNING_BUNDLE", {});
    const auto explicitAnchors = juce::SystemStats::getEnvironmentVariable(
        "LOOP_GENERATOR_C2PA_TRUST_ANCHORS", {});
    const auto explicitConfig = juce::SystemStats::getEnvironmentVariable(
        "LOOP_GENERATOR_C2PA_TRUST_CONFIG", {});

    C2PASigningConfiguration configuration {
        explicitTool.isNotEmpty() ? juce::File(explicitTool)
                                  : support.getChildFile("c2patool"),
        explicitBundle.isNotEmpty() ? juce::File(explicitBundle)
                                    : downloadsSigningBundle(),
        explicitAnchors.isNotEmpty() ? juce::File(explicitAnchors)
                                     : support.getChildFile("trust/test-root-cert.pem"),
        explicitConfig.isNotEmpty() ? juce::File(explicitConfig)
                                    : support.getChildFile("trust/store.cfg")
    };
    if (auto result = configuration.validate(); result.failed())
    {
        error = result.getErrorMessage();
        return std::nullopt;
    }
    return configuration;
}

C2PASigningService::C2PASigningService(
    C2PASigningConfiguration configuration,
    ToolRunner toolRunner)
    : runtime(std::move(configuration)),
      runner(toolRunner ? std::move(toolRunner) : runTool)
{
}

juce::String C2PASigningService::manifestDefinition(
    const C2PASigningConfiguration& configuration,
    const juce::String& modelName,
    const juce::String& modelVersion)
{
    auto root = juce::DynamicObject::Ptr(new juce::DynamicObject());
    root->setProperty("alg", "es256");
    root->setProperty("private_key", configuration.signingBundle.getFullPathName());
    root->setProperty("sign_cert", configuration.signingBundle.getFullPathName());
    root->setProperty("claim_generator", "Loop Generator/" LOOP_GENERATOR_VERSION);
    juce::Array<juce::var> claimGeneratorInfo;
    claimGeneratorInfo.add(juce::var(softwareAgent(
        "Loop Generator", LOOP_GENERATOR_VERSION).get()));
    root->setProperty("claim_generator_info", claimGeneratorInfo);
    root->setProperty("title", "Loop Generator AI Audio");
    root->setProperty("format", "audio/wav");

    auto action = juce::DynamicObject::Ptr(new juce::DynamicObject());
    action->setProperty("action", "c2pa.created");
    action->setProperty("softwareAgent", juce::var(
        softwareAgent(modelName, modelVersion).get()));
    action->setProperty(
        "digitalSourceType",
        "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia");
    action->setProperty(
        "description",
        "AI-generated audio created by Loop Generator using Stable Audio Open Small.");
    juce::Array<juce::var> actions;
    actions.add(juce::var(action.get()));
    auto actionData = juce::DynamicObject::Ptr(new juce::DynamicObject());
    actionData->setProperty("actions", actions);
    auto assertion = juce::DynamicObject::Ptr(new juce::DynamicObject());
    assertion->setProperty("label", "c2pa.actions.v2");
    assertion->setProperty("data", juce::var(actionData.get()));
    juce::Array<juce::var> assertions;
    assertions.add(juce::var(assertion.get()));
    root->setProperty("assertions", assertions);
    return juce::JSON::toString(juce::var(root.get()), true);
}

bool C2PASigningService::validationReportIsTrusted(const juce::String& report)
{
    const auto parsed = juce::JSON::parse(report);
    const auto* root = parsed.getDynamicObject();
    if (root == nullptr || root->getProperty("validation_state").toString() != "Trusted")
        return false;
    const auto* results = root->getProperty("validation_results").getDynamicObject();
    const auto* active = results != nullptr
        ? results->getProperty("activeManifest").getDynamicObject() : nullptr;
    if (active == nullptr)
        return false;
    const auto successes = statusCodes(active->getProperty("success"));
    const auto failures = statusCodes(active->getProperty("failure"));
    return failures.empty()
        && successes.contains("signingCredential.trusted")
        && successes.contains("claimSignature.validated")
        && successes.contains("assertion.dataHash.match")
        && report.contains("c2pa.created")
        && report.contains("trainedAlgorithmicMedia");
}

juce::Result C2PASigningService::signAndValidate(
    const juce::File& audioFile,
    const juce::File& modelMetadataFile) const
{
    if (! audioFile.existsAsFile())
        return juce::Result::fail("Generated WAV is missing before C2PA signing.");
    const auto metadata = juce::JSON::parse(modelMetadataFile.loadFileAsString());
    const auto* metadataObject = metadata.getDynamicObject();
    const auto modelName = metadataObject != nullptr
        ? metadataObject->getProperty("modelName").toString() : juce::String();
    const auto modelVersion = metadataObject != nullptr
        ? metadataObject->getProperty("modelVersion").toString() : juce::String();
    if (modelName.isEmpty() || modelVersion.isEmpty())
        return juce::Result::fail("Stable Audio model metadata is incomplete.");

    const auto manifestFile = audioFile.getSiblingFile(
        "." + audioFile.getFileNameWithoutExtension()
        + "-" + juce::Uuid().toString() + "-c2pa-manifest.json");
    struct ManifestCleanup
    {
        juce::File file;
        ~ManifestCleanup() { file.deleteFile(); }
    } manifestCleanup { manifestFile };
    juce::TemporaryFile signedAudio(audioFile);
    if (! manifestFile.replaceWithText(
            manifestDefinition(runtime, modelName, modelVersion)))
        return juce::Result::fail("Could not create the C2PA manifest definition.");

    const auto signResult = runner({
        runtime.tool.getFullPathName(),
        audioFile.getFullPathName(),
        "--manifest", manifestFile.getFullPathName(),
        "--create", "trainedAlgorithmicMedia",
        "--output", signedAudio.getFile().getFullPathName()
    });
    if (signResult.exitCode != 0 || ! signedAudio.getFile().existsAsFile())
        return juce::Result::fail(
            "C2PA signing failed: " + signResult.output.substring(0, 500));

    const auto validation = runner({
        runtime.tool.getFullPathName(),
        signedAudio.getFile().getFullPathName(),
        "--detailed", "trust",
        "--trust_anchors", runtime.trustAnchors.getFullPathName(),
        "--trust_config", runtime.trustConfig.getFullPathName()
    });
    if (validation.exitCode != 0 || ! validationReportIsTrusted(validation.output))
        return juce::Result::fail(
            "Signed WAV failed C2PA test validation: "
            + validation.output.substring(0, 500));
    if (! signedAudio.overwriteTargetFileWithTemporary())
        return juce::Result::fail("Could not commit the validated C2PA WAV.");
    return juce::Result::ok();
}

C2PAToolResult C2PASigningService::runTool(const juce::StringArray& arguments)
{
    juce::ChildProcess process;
    if (! process.start(arguments))
        return { -1, "Could not start c2patool." };
    process.waitForProcessToFinish(-1);
    return {
        static_cast<int>(process.getExitCode()),
        process.readAllProcessOutput().trim()
    };
}
}
