import AVFoundation
import XCTest
@testable import LoopGeneratorCore

final class LoopGeneratorCoreTests: XCTestCase {
    func testInstrumentIsIncludedInFinalPrompt() throws {
        let request = try GenerationRequest(
            instrument: .bass,
            userPrompt: "warm analog groove, 110 BPM, funky",
            duration: .eight,
            seed: 42
        )
        XCTAssertEqual(request.userPrompt, "warm analog groove, 110 BPM, funky")
        XCTAssertEqual(request.finalPrompt, "Bass loop, warm analog groove, 110 BPM, funky")
    }

    func testSeedPersistsIntoGenerationRecord() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let audioURL = directory.appendingPathComponent("source.wav")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try makeStereoFixture(at: audioURL)

        let store = MemoryRecordStore()
        let controller = GenerationController(
            modelAdapter: StubModelAdapter(audioURL: audioURL),
            recordStore: store,
            randomSeed: { 777 }
        )
        let outcome = try await controller.generate(
            instrument: .drums,
            userPrompt: "tight dry breakbeat",
            duration: .four,
            seed: nil
        )

        XCTAssertEqual(outcome.record.seed, 777)
        let stored = await store.records
        XCTAssertEqual(stored.first?.seed, 777)
    }

    func testGenerationRecordRoundTripsThroughJSON() throws {
        let record = makeRecord(outputAsset: URL(fileURLWithPath: "/tmp/test.wav"))
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(GenerationRecord.self, from: encoded)
        XCTAssertEqual(decoded, record)
    }

    func testWAVEncoderProduces44100Stereo24BitFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.wav")
        let destination = directory.appendingPathComponent("export.wav")
        try makeStereoFixture(at: source)

        try AVFoundationWAVEncoder().encodeWAV(source: source, destination: destination)

        let exported = try AVAudioFile(forReading: destination)
        XCTAssertEqual(exported.processingFormat.sampleRate, 44_100, accuracy: 0.1)
        XCTAssertEqual(exported.processingFormat.channelCount, 2)
        XCTAssertEqual(try wavBitsPerSample(at: destination), 24)
    }

    func testNullProvenanceServiceIsNoOp() async throws {
        let context = ExportContext(
            generationRecord: makeRecord(outputAsset: URL(fileURLWithPath: "/tmp/source.wav")),
            exportedAsset: URL(fileURLWithPath: "/tmp/export.wav")
        )
        try await NullProvenanceService().processExport(context)
    }

    func testModelAdapterFailurePropagatesWithoutCreatingRecord() async {
        let store = MemoryRecordStore()
        let controller = GenerationController(
            modelAdapter: FailingModelAdapter(),
            recordStore: store
        )

        do {
            _ = try await controller.generate(
                instrument: .guitar,
                userPrompt: "clean muted rhythm",
                duration: .four,
                seed: 3
            )
            XCTFail("Expected generation to fail")
        } catch {
            XCTAssertEqual(error as? GenerationError, .generationFailed)
        }
        let stored = await store.records
        XCTAssertTrue(stored.isEmpty)
    }

    func testPartialModelCacheIsNotReportedAsReady() throws {
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let snapshot = cache
            .appendingPathComponent("models--stabilityai--stable-audio-open-small/snapshots/test")
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try Data("license only".utf8).write(to: snapshot.appendingPathComponent("LICENSE"))

        XCTAssertFalse(StableAudioRuntimeConfiguration.containsModelWeights(at: cache))

        try Data("{}".utf8).write(to: snapshot.appendingPathComponent("model_config.json"))
        try Data().write(to: snapshot.appendingPathComponent("model.safetensors"))
        XCTAssertTrue(StableAudioRuntimeConfiguration.containsModelWeights(at: cache))
    }

    func testTextEncoderCacheRequiresTokenizerAndWeights() throws {
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let snapshot = cache.appendingPathComponent("models--t5-base/snapshots/test")
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: snapshot.appendingPathComponent("config.json"))
        XCTAssertFalse(StableAudioRuntimeConfiguration.containsTextEncoder(at: cache))

        try Data().write(to: snapshot.appendingPathComponent("spiece.model"))
        try Data().write(to: snapshot.appendingPathComponent("model.safetensors"))
        XCTAssertTrue(StableAudioRuntimeConfiguration.containsTextEncoder(at: cache))
    }

    func testLiveStableAudioAdapterWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["LOOP_GENERATOR_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set LOOP_GENERATOR_LIVE_TEST=1 to run local model inference")
        }

        let adapter = try StableAudioAdapter()
        let request = try GenerationRequest(
            instrument: .synth,
            userPrompt: "warm analog pulse, instrumental, 110 BPM",
            duration: .four,
            seed: 424_242
        )
        let output = try await adapter.generate(request)

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.audioURL.path))
        XCTAssertEqual(output.sampleRate, 44_100, accuracy: 0.1)
        XCTAssertEqual(output.channelCount, 2)
        XCTAssertEqual(output.durationSeconds, 4, accuracy: 0.01)
        XCTAssertFalse(output.modelVersion.isEmpty)
    }

    private func makeRecord(outputAsset: URL) -> GenerationRecord {
        GenerationRecord(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            instrument: .synth,
            userPrompt: "warm pulse",
            finalPrompt: "Synth loop, warm pulse",
            durationSeconds: 8,
            seed: 42,
            modelName: "Stable Audio Open Small",
            modelVersion: "test-revision",
            generationTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            outputAsset: outputAsset
        )
    }

    private func makeStereoFixture(at url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = file.processingFormat
        let frameCount: AVAudioFrameCount = 4_410
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        for channel in 0..<2 {
            for frame in 0..<Int(frameCount) {
                let phase = Double(frame) / 44_100 * 2 * Double.pi * 220
                buffer.floatChannelData![channel][frame] = Float(sin(phase) * 0.2)
            }
        }
        try file.write(from: buffer)
    }

    private func wavBitsPerSample(at url: URL) throws -> UInt16 {
        let data = try Data(contentsOf: url)
        let marker = Data("fmt ".utf8)
        guard let range = data.range(of: marker), range.lowerBound + 24 <= data.count else {
            throw TestError.invalidWAV
        }
        let offset = range.lowerBound + 22
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
}

private actor MemoryRecordStore: GenerationRecordStoring {
    private(set) var records: [GenerationRecord] = []
    func save(_ record: GenerationRecord) async throws { records.append(record) }
}

private struct StubModelAdapter: ModelAdapter {
    let audioURL: URL
    let modelName = "Stub"

    func generate(_ request: GenerationRequest) async throws -> GeneratedAudio {
        GeneratedAudio(
            audioURL: audioURL,
            durationSeconds: Double(request.durationSeconds),
            sampleRate: 44_100,
            channelCount: 2,
            modelVersion: "stub-1"
        )
    }
}

private struct FailingModelAdapter: ModelAdapter {
    let modelName = "Failing Stub"
    func generate(_ request: GenerationRequest) async throws -> GeneratedAudio {
        throw GenerationError.generationFailed
    }
}

private enum TestError: Error {
    case invalidWAV
}
