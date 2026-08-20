import AVFoundation
import Foundation

public struct StableAudioRuntimeConfiguration: Equatable, Sendable {
    public let pythonExecutable: URL
    public let inferenceScript: URL
    public let modelCache: URL

    public init(
        pythonExecutable: URL,
        inferenceScript: URL,
        modelCache: URL? = nil
    ) {
        self.pythonExecutable = pythonExecutable
        self.inferenceScript = inferenceScript
        self.modelCache = modelCache ?? inferenceScript
            .deletingLastPathComponent()
            .appendingPathComponent(".model-cache")
    }

    public static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) throws -> StableAudioRuntimeConfiguration {
        let fileManager = FileManager.default

        if let pythonPath = environment["LOOP_GENERATOR_PYTHON"],
           let scriptPath = environment["LOOP_GENERATOR_RUNTIME_SCRIPT"],
           fileManager.isExecutableFile(atPath: pythonPath),
           fileManager.fileExists(atPath: scriptPath) {
            return StableAudioRuntimeConfiguration(
                pythonExecutable: URL(fileURLWithPath: pythonPath),
                inferenceScript: URL(fileURLWithPath: scriptPath),
                modelCache: environment["LOOP_GENERATOR_MODEL_CACHE"].map {
                    URL(fileURLWithPath: $0)
                }
            )
        }

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let bundledScript = bundle.resourceURL?
            .appendingPathComponent("runtime/stable_audio/infer.py")
        let sourceScript = sourceRoot.appendingPathComponent("runtime/stable_audio/infer.py")
        let scriptCandidates = [bundledScript, sourceScript].compactMap { $0 }

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let installedPython = applicationSupport
            .appendingPathComponent("LoopGenerator/runtime/.venv/bin/python")
        let installedModelCache = applicationSupport
            .appendingPathComponent("LoopGenerator/runtime/.model-cache")
        let sourcePython = sourceRoot
            .appendingPathComponent("runtime/stable_audio/.venv/bin/python")
        let sourceModelCache = sourceRoot
            .appendingPathComponent("runtime/stable_audio/.model-cache")

        let bundleRoot = bundle.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let adjacentPython = bundleRoot
            .appendingPathComponent("runtime/stable_audio/.venv/bin/python")
        let adjacentModelCache = bundleRoot
            .appendingPathComponent("runtime/stable_audio/.model-cache")
        let pythonCandidates = [installedPython, sourcePython, adjacentPython]
        let modelCacheCandidates = [
            environment["LOOP_GENERATOR_MODEL_CACHE"].map { URL(fileURLWithPath: $0) },
            installedModelCache,
            sourceModelCache,
            adjacentModelCache
        ].compactMap { $0 }

        guard let script = scriptCandidates.first(where: {
            fileManager.fileExists(atPath: $0.path)
        }), let python = pythonCandidates.first(where: {
            fileManager.isExecutableFile(atPath: $0.path)
        }) else {
            throw GenerationError.modelUnavailable
        }

        let modelCache = modelCacheCandidates.first {
            containsModelWeights(at: $0, fileManager: fileManager)
                && containsTextEncoder(at: $0, fileManager: fileManager)
        }
        guard let modelCache else {
            throw GenerationError.modelUnavailable
        }

        return StableAudioRuntimeConfiguration(
            pythonExecutable: python,
            inferenceScript: script,
            modelCache: modelCache
        )
    }

    static func containsModelWeights(
        at modelCache: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let snapshotsDirectory = modelCache
            .appendingPathComponent("models--stabilityai--stable-audio-open-small")
            .appendingPathComponent("snapshots")
        guard let snapshots = try? fileManager.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }
        return snapshots.contains { snapshot in
            let config = snapshot.appendingPathComponent("model_config.json")
            let safetensors = snapshot.appendingPathComponent("model.safetensors")
            let checkpoint = snapshot.appendingPathComponent("model.ckpt")
            return fileManager.fileExists(atPath: config.path)
                && (fileManager.fileExists(atPath: safetensors.path)
                    || fileManager.fileExists(atPath: checkpoint.path))
        }
    }

    static func containsTextEncoder(
        at modelCache: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let snapshotsDirectory = modelCache
            .appendingPathComponent("models--t5-base")
            .appendingPathComponent("snapshots")
        guard let snapshots = try? fileManager.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }
        return snapshots.contains { snapshot in
            let config = snapshot.appendingPathComponent("config.json")
            let sentencePiece = snapshot.appendingPathComponent("spiece.model")
            let safetensors = snapshot.appendingPathComponent("model.safetensors")
            let pytorchWeights = snapshot.appendingPathComponent("pytorch_model.bin")
            return fileManager.fileExists(atPath: config.path)
                && fileManager.fileExists(atPath: sentencePiece.path)
                && (fileManager.fileExists(atPath: safetensors.path)
                    || fileManager.fileExists(atPath: pytorchWeights.path))
        }
    }
}

public final class StableAudioAdapter: ModelAdapter, @unchecked Sendable {
    public let modelName = "Stable Audio Open Small"
    private let runtime: StableAudioRuntimeConfiguration
    private let fileManager: FileManager

    public init(
        runtime: StableAudioRuntimeConfiguration? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.runtime = try runtime ?? .discover()
        self.fileManager = fileManager
    }

    public func generate(_ request: GenerationRequest) async throws -> GeneratedAudio {
        try await Task.detached(priority: .userInitiated) { [runtime, fileManager] in
            let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("LoopGenerator", isDirectory: true)
                .appendingPathComponent("generated", isDirectory: true)
            try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

            let stem = UUID().uuidString
            let outputURL = cacheRoot.appendingPathComponent("\(stem).wav")
            let metadataURL = cacheRoot.appendingPathComponent("\(stem).model.json")
            let logURL = cacheRoot.appendingPathComponent("\(stem).log")
            fileManager.createFile(atPath: logURL.path, contents: nil)
            let logHandle = try FileHandle(forWritingTo: logURL)
            defer { try? logHandle.close() }

            let process = Process()
            process.executableURL = runtime.pythonExecutable
            process.currentDirectoryURL = runtime.inferenceScript.deletingLastPathComponent()
            process.arguments = [
                runtime.inferenceScript.path,
                "--prompt", request.finalPrompt,
                "--seconds", String(request.durationSeconds),
                "--seed", String(request.seed),
                "--output", outputURL.path,
                "--metadata-output", metadataURL.path
            ]
            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            environment["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
            environment["TOKENIZERS_PARALLELISM"] = "false"
            environment["HF_HUB_CACHE"] = runtime.modelCache.path
            process.environment = environment
            process.standardOutput = logHandle
            process.standardError = logHandle

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                throw GenerationError.modelUnavailable
            }

            guard process.terminationStatus == 0,
                  fileManager.fileExists(atPath: outputURL.path) else {
                throw GenerationError.generationFailed
            }

            let audioFile = try AVAudioFile(forReading: outputURL)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            let modelVersion: String
            if let data = try? Data(contentsOf: metadataURL),
               let metadata = try? JSONDecoder().decode(RuntimeMetadata.self, from: data) {
                modelVersion = metadata.modelVersion
            } else {
                modelVersion = "stabilityai/stable-audio-open-small"
            }

            return GeneratedAudio(
                audioURL: outputURL,
                durationSeconds: duration,
                sampleRate: audioFile.processingFormat.sampleRate,
                channelCount: Int(audioFile.processingFormat.channelCount),
                modelVersion: modelVersion
            )
        }.value
    }
}

private struct RuntimeMetadata: Decodable {
    let modelVersion: String
}
