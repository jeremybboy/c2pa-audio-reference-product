import Foundation

public final class C2PAProvenanceService: ProvenanceService, @unchecked Sendable {
    private let manifestBuilder: C2PAManifestBuilder
    private let credentialProvider: any SigningCredentialProvider
    private let toolRunner: any C2PAToolRunning
    private let evidenceStore: any C2PAEvidenceStoring
    private let fileManager: FileManager

    public convenience init(
        applicationVersion: String,
        runtime: C2PARuntimeConfiguration? = nil,
        evidenceStore: any C2PAEvidenceStoring = JSONC2PAEvidenceStore()
    ) throws {
        let resolvedRuntime = try runtime ?? .discover()
        let credential = SigningCredential(
            certificateURL: resolvedRuntime.certificateURL,
            privateKeyURL: resolvedRuntime.privateKeyURL
        )
        self.init(
            manifestBuilder: C2PAManifestBuilder(applicationVersion: applicationVersion),
            credentialProvider: FileSigningCredentialProvider(credential: credential),
            toolRunner: C2PAToolRunner(configuration: resolvedRuntime),
            evidenceStore: evidenceStore
        )
    }

    public init(
        manifestBuilder: C2PAManifestBuilder,
        credentialProvider: any SigningCredentialProvider,
        toolRunner: any C2PAToolRunning,
        evidenceStore: any C2PAEvidenceStoring,
        fileManager: FileManager = .default
    ) {
        self.manifestBuilder = manifestBuilder
        self.credentialProvider = credentialProvider
        self.toolRunner = toolRunner
        self.evidenceStore = evidenceStore
        self.fileManager = fileManager
    }

    public func processExport(_ context: ExportContext) async throws {
        let credential = try credentialProvider.credential()
        let manifestData = try manifestBuilder.manifestData(
            for: context.generationRecord,
            credential: credential
        )
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("LoopGenerator-C2PA-\(UUID().uuidString)", isDirectory: true)
        let manifestURL = workDirectory.appendingPathComponent("manifest-definition.json")
        let signedURL = workDirectory.appendingPathComponent("signed.wav")

        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDirectory) }
        do {
            try manifestData.write(to: manifestURL, options: .atomic)
        } catch {
            throw ProvenanceError.manifestConstructionFailed
        }

        try await toolRunner.sign(
            source: context.exportedAsset,
            manifest: manifestURL,
            destination: signedURL
        )
        let validationData = try await toolRunner.validate(asset: signedURL)
        let inspection = try C2PAValidationInspection.inspect(validationData)
        guard inspection.satisfiesV1Profile(
            applicationVersion: manifestBuilder.applicationVersion,
            modelName: context.generationRecord.modelName,
            modelVersion: context.generationRecord.modelVersion
        ) else {
            throw ProvenanceError.validationFailed
        }

        do {
            _ = try fileManager.replaceItemAt(context.exportedAsset, withItemAt: signedURL)
        } catch {
            throw ProvenanceError.signingFailed
        }
        try evidenceStore.save(
            recordID: context.generationRecord.id,
            manifestJSON: inspection.activeManifestJSON,
            validationJSON: validationData
        )
    }
}
