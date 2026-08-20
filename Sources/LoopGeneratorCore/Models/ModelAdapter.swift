import Foundation

public protocol ModelAdapter: Sendable {
    var modelName: String { get }
    func generate(_ request: GenerationRequest) async throws -> GeneratedAudio
}

public final class GenerationController: @unchecked Sendable {
    private let modelAdapter: any ModelAdapter
    private let recordStore: any GenerationRecordStoring
    private let now: @Sendable () -> Date
    private let randomSeed: @Sendable () -> Int64

    public init(
        modelAdapter: any ModelAdapter,
        recordStore: any GenerationRecordStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        randomSeed: @escaping @Sendable () -> Int64 = {
            Int64.random(in: 0...Int64.max)
        }
    ) {
        self.modelAdapter = modelAdapter
        self.recordStore = recordStore
        self.now = now
        self.randomSeed = randomSeed
    }

    public func generate(
        instrument: InstrumentCategory,
        userPrompt: String,
        duration: GenerationDuration,
        seed: Int64?
    ) async throws -> GenerationOutcome {
        let resolvedSeed = seed ?? randomSeed()
        let request = try GenerationRequest(
            instrument: instrument,
            userPrompt: userPrompt,
            duration: duration,
            seed: resolvedSeed
        )

        let audio = try await modelAdapter.generate(request)
        let record = GenerationRecord(
            instrument: request.instrument,
            userPrompt: request.userPrompt,
            finalPrompt: request.finalPrompt,
            durationSeconds: request.durationSeconds,
            seed: request.seed,
            modelName: modelAdapter.modelName,
            modelVersion: audio.modelVersion,
            generationTimestamp: now(),
            outputAsset: audio.audioURL
        )
        try await recordStore.save(record)
        return GenerationOutcome(record: record, audio: audio)
    }
}
