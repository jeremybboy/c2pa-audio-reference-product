import AVFoundation
import CryptoKit
import Foundation
import LoopGeneratorCore

@main
enum LoopGeneratorC2PAVerify {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(
                Data("C2PA verification failed: \(error.localizedDescription)\n".utf8)
            )
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        guard CommandLine.arguments.count == 5 else {
            throw VerificationError.usage
        }
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let metadataURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let evidenceDirectory = URL(
            fileURLWithPath: CommandLine.arguments[3],
            isDirectory: true
        )
        let applicationVersion = CommandLine.arguments[4]
        guard FileManager.default.isReadableFile(atPath: sourceURL.path),
              FileManager.default.isReadableFile(atPath: metadataURL.path) else {
            throw VerificationError.missingModelEvidence
        }
        let metadata = try JSONDecoder().decode(
            ModelMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        guard metadata.modelName == "Stable Audio Open Small",
              metadata.modelVersion.count == 40,
              metadata.sampleRate == 44_100,
              metadata.channels == 2 else {
            throw VerificationError.invalidModelEvidence
        }

        try FileManager.default.createDirectory(
            at: evidenceDirectory,
            withIntermediateDirectories: true
        )
        let unsignedURL = evidenceDirectory.appendingPathComponent("unsigned-source.wav")
        let signedURL = evidenceDirectory.appendingPathComponent("signed-c2pa.wav")
        let tamperedURL = evidenceDirectory.appendingPathComponent("tampered-c2pa.wav")
        let validationURL = evidenceDirectory.appendingPathComponent("validation-report.json")
        let negativeURL = evidenceDirectory.appendingPathComponent(
            "negative-validation-report.json"
        )
        let manifestURL = evidenceDirectory.appendingPathComponent("manifest.json")
        let summaryURL = evidenceDirectory.appendingPathComponent("evidence-summary.json")
        for file in [
            unsignedURL,
            signedURL,
            tamperedURL,
            validationURL,
            negativeURL,
            manifestURL,
            summaryURL
        ] where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }

        let encoder = AVFoundationWAVEncoder()
        try encoder.encodeWAV(source: sourceURL, destination: unsignedURL)
        let record = GenerationRecord(
            instrument: .synth,
            userPrompt: "warm analog pulse, instrumental, 110 BPM",
            finalPrompt: "Synth loop, warm analog pulse, instrumental, 110 BPM",
            durationSeconds: metadata.durationSeconds,
            seed: metadata.seed,
            modelName: metadata.modelName,
            modelVersion: metadata.modelVersion,
            outputAsset: sourceURL
        )
        let runtime = try C2PARuntimeConfiguration.discover()
        let provenance = try C2PAProvenanceService(
            applicationVersion: applicationVersion,
            runtime: runtime,
            evidenceStore: JSONC2PAEvidenceStore(
                directoryURL: evidenceDirectory.appendingPathComponent(
                    "service-evidence",
                    isDirectory: true
                )
            )
        )
        let exportService = ExportService(
            encoder: encoder,
            provenanceService: provenance
        )
        try await exportService.exportWAV(record: record, destination: signedURL)

        let toolRunner = C2PAToolRunner(configuration: runtime)
        let validationData = try await toolRunner.validate(asset: signedURL)
        let positive = try C2PAValidationInspection.inspect(validationData)
        guard positive.satisfiesV1Profile(
            applicationVersion: applicationVersion,
            modelName: metadata.modelName,
            modelVersion: metadata.modelVersion
        ) else {
            throw VerificationError.profileValidationFailed
        }
        try validationData.write(to: validationURL, options: .atomic)
        try positive.activeManifestJSON.write(to: manifestURL, options: .atomic)

        var tamperedBytes = try Data(contentsOf: signedURL)
        guard tamperedBytes.count > 1_000 else {
            throw VerificationError.invalidSignedAsset
        }
        tamperedBytes[1_000] ^= 1
        try tamperedBytes.write(to: tamperedURL, options: .atomic)
        let negativeData = try await toolRunner.validate(asset: tamperedURL)
        let negative = try C2PAValidationInspection.inspect(negativeData)
        guard negative.detectsTampering else {
            throw VerificationError.tamperWasNotDetected
        }
        try negativeData.write(to: negativeURL, options: .atomic)

        let signedAudio = try AVAudioFile(forReading: signedURL)
        guard abs(signedAudio.processingFormat.sampleRate - 44_100) < 0.1,
              signedAudio.processingFormat.channelCount == 2,
              try wavBitsPerSample(at: signedURL) == 24 else {
            throw VerificationError.invalidSignedAsset
        }
        let summary = EvidenceSummary(
            applicationVersion: applicationVersion,
            modelName: metadata.modelName,
            modelVersion: metadata.modelVersion,
            c2patoolVersion: C2PARuntimeConfiguration.c2paToolVersion,
            c2paSDKVersion: C2PARuntimeConfiguration.c2paSDKVersion,
            conformanceToolCommit: C2PARuntimeConfiguration.conformanceToolCommit,
            testModeEnabled: true,
            testRootCommonName: "C2PA Conformance Test Root",
            testSigningCommonName: "C2PA Conformance Test Signing",
            sampleRate: 44_100,
            channels: 2,
            bitsPerSample: 24,
            activeManifestCount: positive.manifestCount,
            validationState: positive.validationState,
            tamperValidationState: negative.validationState,
            tamperFailureCodes: negative.failureCodes.sorted(),
            profileConforms: true,
            containsIngredients: positive.containsIngredients,
            containsPromptOrSeed: positive.containsPromptOrSeed,
            containsAllActionsIncluded: positive.containsAllActionsIncluded,
            unsignedSHA256: try sha256(of: unsignedURL),
            signedSHA256: try sha256(of: signedURL),
            tamperedSHA256: try sha256(of: tamperedURL)
        )
        let encoderJSON = JSONEncoder()
        encoderJSON.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoderJSON.encode(summary).write(to: summaryURL, options: .atomic)

        print("C2PA V1 evidence written to \(evidenceDirectory.path)")
        print("positive validation: \(positive.validationState)")
        print("negative validation: \(negative.validationState)")
    }

    private static func wavBitsPerSample(at url: URL) throws -> UInt16 {
        let data = try Data(contentsOf: url)
        let marker = Data("fmt ".utf8)
        guard let range = data.range(of: marker), range.lowerBound + 24 <= data.count else {
            throw VerificationError.invalidSignedAsset
        }
        let offset = range.lowerBound + 22
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func sha256(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct ModelMetadata: Decodable {
    let modelName: String
    let modelVersion: String
    let sampleRate: Int
    let channels: Int
    let durationSeconds: Int
    let seed: Int64
}

private struct EvidenceSummary: Encodable {
    let applicationVersion: String
    let modelName: String
    let modelVersion: String
    let c2patoolVersion: String
    let c2paSDKVersion: String
    let conformanceToolCommit: String
    let testModeEnabled: Bool
    let testRootCommonName: String
    let testSigningCommonName: String
    let sampleRate: Int
    let channels: Int
    let bitsPerSample: Int
    let activeManifestCount: Int
    let validationState: String
    let tamperValidationState: String
    let tamperFailureCodes: [String]
    let profileConforms: Bool
    let containsIngredients: Bool
    let containsPromptOrSeed: Bool
    let containsAllActionsIncluded: Bool
    let unsignedSHA256: String
    let signedSHA256: String
    let tamperedSHA256: String
}

private enum VerificationError: LocalizedError {
    case usage
    case missingModelEvidence
    case invalidModelEvidence
    case profileValidationFailed
    case invalidSignedAsset
    case tamperWasNotDetected

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: LoopGeneratorC2PAVerify <model WAV> <model JSON> <evidence dir> <app version>"
        case .missingModelEvidence:
            "Real Stable Audio model evidence is missing."
        case .invalidModelEvidence:
            "Stable Audio model evidence is incomplete or unexpected."
        case .profileValidationFailed:
            "The signed WAV does not satisfy the frozen C2PA V1 profile."
        case .invalidSignedAsset:
            "The signed asset is not a 44.1 kHz stereo 24-bit PCM WAV."
        case .tamperWasNotDetected:
            "The negative tamper test did not fail the hard binding."
        }
    }
}
