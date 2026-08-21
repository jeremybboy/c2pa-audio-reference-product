import Foundation

public protocol C2PAEvidenceStoring: Sendable {
    func save(
        recordID: UUID,
        manifestJSON: Data,
        validationJSON: Data
    ) throws
}

public struct JSONC2PAEvidenceStore: C2PAEvidenceStoring {
    private let directoryURL: URL

    public init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.directoryURL = applicationSupport
                .appendingPathComponent("LoopGenerator/c2pa-evidence", isDirectory: true)
        }
    }

    public func save(
        recordID: UUID,
        manifestJSON: Data,
        validationJSON: Data
    ) throws {
        let recordDirectory = directoryURL
            .appendingPathComponent(recordID.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: recordDirectory,
                withIntermediateDirectories: true
            )
            try manifestJSON.write(
                to: recordDirectory.appendingPathComponent("manifest.json"),
                options: .atomic
            )
            try validationJSON.write(
                to: recordDirectory.appendingPathComponent("validation.json"),
                options: .atomic
            )
        } catch {
            throw ProvenanceError.evidenceWriteFailed
        }
    }
}
