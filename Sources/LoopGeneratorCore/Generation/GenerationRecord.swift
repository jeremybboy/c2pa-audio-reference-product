import Foundation

public struct GenerationRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let instrument: InstrumentCategory
    public let userPrompt: String
    public let finalPrompt: String
    public let durationSeconds: Int
    public let seed: Int64
    public let modelName: String
    public let modelVersion: String
    public let generationTimestamp: Date
    public let outputAsset: URL

    public init(
        id: UUID = UUID(),
        instrument: InstrumentCategory,
        userPrompt: String,
        finalPrompt: String,
        durationSeconds: Int,
        seed: Int64,
        modelName: String,
        modelVersion: String,
        generationTimestamp: Date = Date(),
        outputAsset: URL
    ) {
        self.id = id
        self.instrument = instrument
        self.userPrompt = userPrompt
        self.finalPrompt = finalPrompt
        self.durationSeconds = durationSeconds
        self.seed = seed
        self.modelName = modelName
        self.modelVersion = modelVersion
        self.generationTimestamp = generationTimestamp
        self.outputAsset = outputAsset
    }
}

public protocol GenerationRecordStoring: Sendable {
    func save(_ record: GenerationRecord) async throws
}

public actor JSONGenerationRecordStore: GenerationRecordStoring {
    private let directoryURL: URL
    private let encoder: JSONEncoder

    public init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.directoryURL = applicationSupport
                .appendingPathComponent("LoopGenerator", isDirectory: true)
                .appendingPathComponent("generations", isDirectory: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func save(_ record: GenerationRecord) async throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let destination = directoryURL.appendingPathComponent("\(record.id.uuidString).json")
        try encoder.encode(record).write(to: destination, options: .atomic)
    }
}
