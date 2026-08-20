import Foundation

public protocol AudioExportEncoding: Sendable {
    func encodeWAV(source: URL, destination: URL) throws
}

public protocol ExportServing: Sendable {
    func exportWAV(record: GenerationRecord, destination: URL) async throws
}

public final class ExportService: ExportServing, @unchecked Sendable {
    private let encoder: any AudioExportEncoding
    private let provenanceService: any ProvenanceService

    public init(
        encoder: any AudioExportEncoding,
        provenanceService: any ProvenanceService
    ) {
        self.encoder = encoder
        self.provenanceService = provenanceService
    }

    public func exportWAV(record: GenerationRecord, destination: URL) async throws {
        do {
            try encoder.encodeWAV(source: record.outputAsset, destination: destination)
            let context = ExportContext(
                generationRecord: record,
                exportedAsset: destination
            )
            try await provenanceService.processExport(context)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw ExportError.wavExportFailed
        }
    }
}

public enum ExportError: LocalizedError {
    case invalidSourceFormat
    case wavExportFailed

    public var errorDescription: String? {
        switch self {
        case .invalidSourceFormat:
            return "Generated audio is not 44.1 kHz stereo."
        case .wavExportFailed:
            return "WAV export failed."
        }
    }
}
