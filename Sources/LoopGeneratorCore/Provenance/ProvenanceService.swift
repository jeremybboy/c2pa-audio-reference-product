import Foundation

public struct ExportContext: Equatable, Sendable {
    public let generationRecord: GenerationRecord
    public let exportedAsset: URL

    public init(generationRecord: GenerationRecord, exportedAsset: URL) {
        self.generationRecord = generationRecord
        self.exportedAsset = exportedAsset
    }
}

public protocol ProvenanceService: Sendable {
    func processExport(_ context: ExportContext) async throws
}

public struct NullProvenanceService: ProvenanceService {
    public init() {}

    public func processExport(_ context: ExportContext) async throws {
        // Deliberate V0 no-op. C2PA processing will be inserted here.
    }
}
