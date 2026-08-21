import Foundation

public struct C2PAManifestBuilder: Sendable {
    public static let actionLabel = "c2pa.actions.v2"
    public static let creationAction = "c2pa.created"
    public static let digitalSourceType =
        "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia"
    public static let actionDescription =
        "AI-generated audio created by Loop Generator using Stable Audio Open Small."

    public let applicationVersion: String

    public init(applicationVersion: String) {
        self.applicationVersion = applicationVersion
    }

    public func manifestData(
        for record: GenerationRecord,
        credential: SigningCredential
    ) throws -> Data {
        let manifest = ManifestDefinition(
            alg: credential.algorithm,
            privateKey: credential.privateKeyURL.path,
            signCert: credential.certificateURL.path,
            claimGenerator: "Loop Generator/\(applicationVersion)",
            claimGeneratorInfo: [
                SoftwareAgent(name: "Loop Generator", version: applicationVersion)
            ],
            title: "Loop Generator AI Audio",
            format: "audio/wav",
            assertions: [
                AssertionDefinition(
                    label: Self.actionLabel,
                    data: ActionsData(actions: [
                        ActionDefinition(
                            action: Self.creationAction,
                            softwareAgent: SoftwareAgent(
                                name: record.modelName,
                                version: record.modelVersion
                            ),
                            digitalSourceType: Self.digitalSourceType,
                            description: Self.actionDescription
                        )
                    ])
                )
            ]
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(manifest)
        } catch {
            throw ProvenanceError.manifestConstructionFailed
        }
    }
}

private struct ManifestDefinition: Encodable {
    let alg: String
    let privateKey: String
    let signCert: String
    let claimGenerator: String
    let claimGeneratorInfo: [SoftwareAgent]
    let title: String
    let format: String
    let assertions: [AssertionDefinition]

    enum CodingKeys: String, CodingKey {
        case alg
        case privateKey = "private_key"
        case signCert = "sign_cert"
        case claimGenerator = "claim_generator"
        case claimGeneratorInfo = "claim_generator_info"
        case title
        case format
        case assertions
    }
}

private struct AssertionDefinition: Encodable {
    let label: String
    let data: ActionsData
}

private struct ActionsData: Encodable {
    let actions: [ActionDefinition]
}

private struct ActionDefinition: Encodable {
    let action: String
    let softwareAgent: SoftwareAgent
    let digitalSourceType: String
    let description: String
}

private struct SoftwareAgent: Encodable {
    let name: String
    let version: String
}
