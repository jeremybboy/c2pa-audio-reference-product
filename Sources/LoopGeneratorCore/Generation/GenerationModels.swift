import Foundation

public enum InstrumentCategory: String, CaseIterable, Codable, Sendable {
    case synth = "Synth"
    case bass = "Bass"
    case drums = "Drums"
    case piano = "Piano"
    case guitar = "Guitar"
    case strings = "Strings"
    case fx = "FX"

    public var promptPrefix: String {
        "\(rawValue) loop"
    }
}

public enum GenerationDuration: Int, CaseIterable, Codable, Sendable, Identifiable {
    case four = 4
    case eight = 8
    case eleven = 11

    public var id: Int { rawValue }
    public var label: String { "\(rawValue) seconds" }
}

public struct GenerationRequest: Codable, Equatable, Sendable {
    public let instrument: InstrumentCategory
    public let userPrompt: String
    public let finalPrompt: String
    public let durationSeconds: Int
    public let seed: Int64

    public init(
        instrument: InstrumentCategory,
        userPrompt: String,
        duration: GenerationDuration,
        seed: Int64
    ) throws {
        let normalizedPrompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty else {
            throw GenerationError.emptyPrompt
        }
        guard normalizedPrompt.count <= 200 else {
            throw GenerationError.promptTooLong
        }

        self.instrument = instrument
        self.userPrompt = normalizedPrompt
        self.finalPrompt = "\(instrument.promptPrefix), \(normalizedPrompt)"
        self.durationSeconds = duration.rawValue
        self.seed = seed
    }
}

public struct GeneratedAudio: Equatable, Sendable {
    public let audioURL: URL
    public let durationSeconds: Double
    public let sampleRate: Double
    public let channelCount: Int
    public let modelVersion: String

    public init(
        audioURL: URL,
        durationSeconds: Double,
        sampleRate: Double,
        channelCount: Int,
        modelVersion: String
    ) {
        self.audioURL = audioURL
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.modelVersion = modelVersion
    }
}

public struct GenerationOutcome: Equatable, Sendable {
    public let record: GenerationRecord
    public let audio: GeneratedAudio
}

public enum GenerationError: LocalizedError, Equatable {
    case emptyPrompt
    case promptTooLong
    case invalidSeed
    case modelUnavailable
    case generationFailed

    public var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            return "Enter a prompt before generating."
        case .promptTooLong:
            return "Keep the prompt to 200 characters or fewer."
        case .invalidSeed:
            return "Seed must be a whole number from 0 to 9,223,372,036,854,775,807."
        case .modelUnavailable:
            return "Model could not be loaded."
        case .generationFailed:
            return "Generation failed."
        }
    }
}
