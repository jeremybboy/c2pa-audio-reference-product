import Foundation

public struct C2PAValidationInspection: Equatable, Sendable {
    public let validationState: String
    public let manifestCount: Int
    public let actions: [String]
    public let digitalSourceTypes: [String]
    public let claimGeneratorName: String?
    public let claimGeneratorVersion: String?
    public let softwareAgentNames: [String]
    public let softwareAgentVersions: [String]
    public let actionDescriptions: [String]
    public let containsIngredients: Bool
    public let containsPromptOrSeed: Bool
    public let containsAllActionsIncluded: Bool
    public let successCodes: Set<String>
    public let failureCodes: Set<String>
    public let activeManifestJSON: Data

    public var satisfiesV1Profile: Bool {
        validationState == "Trusted"
            && manifestCount == 1
            && actions == [C2PAManifestBuilder.creationAction]
            && digitalSourceTypes == [C2PAManifestBuilder.digitalSourceType]
            && claimGeneratorName == "Loop Generator"
            && !(claimGeneratorVersion?.isEmpty ?? true)
            && softwareAgentNames == ["Stable Audio Open Small"]
            && softwareAgentVersions.count == 1
            && !(softwareAgentVersions.first?.isEmpty ?? true)
            && actionDescriptions == [C2PAManifestBuilder.actionDescription]
            && !containsIngredients
            && !containsPromptOrSeed
            && !containsAllActionsIncluded
            && failureCodes.isEmpty
            && successCodes.contains("signingCredential.trusted")
            && successCodes.contains("claimSignature.validated")
            && successCodes.contains("assertion.dataHash.match")
    }

    public func satisfiesV1Profile(
        applicationVersion: String,
        modelName: String,
        modelVersion: String
    ) -> Bool {
        satisfiesV1Profile
            && claimGeneratorVersion == applicationVersion
            && softwareAgentNames == [modelName]
            && softwareAgentVersions == [modelVersion]
    }

    public var detectsTampering: Bool {
        validationState == "Invalid"
            && failureCodes.contains("assertion.dataHash.mismatch")
    }

    public static func inspect(_ reportData: Data) throws -> C2PAValidationInspection {
        guard let root = try JSONSerialization.jsonObject(with: reportData) as? [String: Any],
              let validationState = root["validation_state"] as? String,
              let activeLabel = root["active_manifest"] as? String,
              let manifests = root["manifests"] as? [String: Any],
              let activeManifest = manifests[activeLabel] as? [String: Any],
              let actionObjects = actionObjects(in: activeManifest) else {
            throw ProvenanceError.validationFailed
        }

        let actions = actionObjects.compactMap { $0["action"] as? String }
        let sourceTypes = actionObjects.compactMap { $0["digitalSourceType"] as? String }
        let softwareAgents = actionObjects.compactMap {
            $0["softwareAgent"] as? [String: Any]
        }
        let claimGenerator = claimGeneratorInfo(in: activeManifest)
        let activeResults = ((root["validation_results"] as? [String: Any])?["activeManifest"]
            as? [String: Any]) ?? [:]
        let successCodes = statusCodes(in: activeResults["success"])
        let failureCodes = statusCodes(in: activeResults["failure"])
        let lowercasedKeys = recursivelyCollectedKeys(in: activeManifest).map {
            $0.lowercased()
        }
        let manifestJSON = try JSONSerialization.data(
            withJSONObject: activeManifest,
            options: [.prettyPrinted, .sortedKeys]
        )

        return C2PAValidationInspection(
            validationState: validationState,
            manifestCount: manifests.count,
            actions: actions,
            digitalSourceTypes: sourceTypes,
            claimGeneratorName: claimGenerator?["name"] as? String,
            claimGeneratorVersion: claimGenerator?["version"] as? String,
            softwareAgentNames: softwareAgents.compactMap { $0["name"] as? String },
            softwareAgentVersions: softwareAgents.compactMap { $0["version"] as? String },
            actionDescriptions: actionObjects.compactMap { $0["description"] as? String },
            containsIngredients: lowercasedKeys.contains(where: { $0.contains("ingredient") }),
            containsPromptOrSeed: lowercasedKeys.contains("prompt")
                || lowercasedKeys.contains("seed"),
            containsAllActionsIncluded: lowercasedKeys.contains("allactionsincluded"),
            successCodes: successCodes,
            failureCodes: failureCodes,
            activeManifestJSON: manifestJSON
        )
    }

    private static func actionObjects(
        in activeManifest: [String: Any]
    ) -> [[String: Any]]? {
        if let assertionStore = activeManifest["assertion_store"] as? [String: Any],
           let actionsAssertion = assertionStore[C2PAManifestBuilder.actionLabel]
            as? [String: Any] {
            return actionsAssertion["actions"] as? [[String: Any]]
        }
        guard let assertions = activeManifest["assertions"] as? [[String: Any]],
              let actionsAssertion = assertions.first(where: {
                  $0["label"] as? String == C2PAManifestBuilder.actionLabel
              }),
              let data = actionsAssertion["data"] as? [String: Any] else {
            return nil
        }
        return data["actions"] as? [[String: Any]]
    }

    private static func claimGeneratorInfo(
        in activeManifest: [String: Any]
    ) -> [String: Any]? {
        if let claim = activeManifest["claim"] as? [String: Any],
           let info = claim["claim_generator_info"] as? [String: Any] {
            return info
        }
        if let info = activeManifest["claim_generator_info"] as? [String: Any] {
            return info
        }
        if let info = activeManifest["claim_generator_info"] as? [[String: Any]] {
            return info.first
        }
        return nil
    }

    private static func statusCodes(in value: Any?) -> Set<String> {
        guard let entries = value as? [[String: Any]] else { return [] }
        return Set(entries.compactMap { $0["code"] as? String })
    }

    private static func recursivelyCollectedKeys(in value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, child in
                [key] + recursivelyCollectedKeys(in: child)
            }
        }
        if let array = value as? [Any] {
            return array.flatMap(recursivelyCollectedKeys)
        }
        return []
    }
}
