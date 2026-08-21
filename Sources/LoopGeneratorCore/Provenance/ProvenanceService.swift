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

public enum ProvenanceError: LocalizedError, Equatable {
    case toolUnavailable
    case credentialUnavailable
    case manifestConstructionFailed
    case signingFailed
    case validationFailed
    case evidenceWriteFailed

    public var errorDescription: String? {
        switch self {
        case .toolUnavailable:
            return "C2PA tooling is not installed."
        case .credentialUnavailable:
            return "C2PA test signing credentials are not installed."
        case .manifestConstructionFailed:
            return "C2PA manifest construction failed."
        case .signingFailed:
            return "C2PA signing failed."
        case .validationFailed:
            return "The signed WAV did not pass C2PA test-root validation."
        case .evidenceWriteFailed:
            return "C2PA evidence could not be saved."
        }
    }
}
