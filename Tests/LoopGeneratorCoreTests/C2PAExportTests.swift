import AVFoundation
import XCTest
@testable import LoopGeneratorCore

final class C2PAExportTests: XCTestCase {
    func testManifestMatchesFrozenV1ProfileWithoutSensitiveGenerationInputs() throws {
        let credential = SigningCredential(
            certificateURL: URL(fileURLWithPath: "/external/test-signing-bundle.pem"),
            privateKeyURL: URL(fileURLWithPath: "/external/test-signing-bundle.pem")
        )
        let data = try C2PAManifestBuilder(applicationVersion: "0.2.0")
            .manifestData(for: makeRecord(), credential: credential)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let assertions = try XCTUnwrap(root["assertions"] as? [[String: Any]])
        let actionAssertion = try XCTUnwrap(assertions.first)
        let actionData = try XCTUnwrap(actionAssertion["data"] as? [String: Any])
        let actions = try XCTUnwrap(actionData["actions"] as? [[String: Any]])
        let action = try XCTUnwrap(actions.first)
        let softwareAgent = try XCTUnwrap(action["softwareAgent"] as? [String: Any])
        let claimGeneratorInfo = try XCTUnwrap(
            (root["claim_generator_info"] as? [[String: Any]])?.first
        )

        XCTAssertEqual(root["alg"] as? String, "es256")
        XCTAssertEqual(root["private_key"] as? String, credential.privateKeyURL.path)
        XCTAssertEqual(root["sign_cert"] as? String, credential.certificateURL.path)
        XCTAssertEqual(root["claim_generator"] as? String, "Loop Generator/0.2.0")
        XCTAssertEqual(claimGeneratorInfo["name"] as? String, "Loop Generator")
        XCTAssertEqual(claimGeneratorInfo["version"] as? String, "0.2.0")
        XCTAssertEqual(actionAssertion["label"] as? String, "c2pa.actions.v2")
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(action["action"] as? String, "c2pa.created")
        XCTAssertEqual(
            action["digitalSourceType"] as? String,
            C2PAManifestBuilder.digitalSourceType
        )
        XCTAssertEqual(softwareAgent["name"] as? String, "Stable Audio Open Small")
        XCTAssertEqual(softwareAgent["version"] as? String, "test-revision")
        XCTAssertEqual(
            action["description"] as? String,
            C2PAManifestBuilder.actionDescription
        )

        let keys = recursivelyCollectedKeys(in: root).map { $0.lowercased() }
        XCTAssertFalse(keys.contains(where: { $0.contains("ingredient") }))
        XCTAssertFalse(keys.contains("prompt"))
        XCTAssertFalse(keys.contains("seed"))
        XCTAssertFalse(keys.contains("allactionsincluded"))
        XCTAssertNil(root["ta_url"])
    }

    func testFileCredentialProviderRejectsMissingExternalBundle() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let provider = FileSigningCredentialProvider(
            credential: SigningCredential(
                certificateURL: missing,
                privateKeyURL: missing
            )
        )
        XCTAssertThrowsError(try provider.credential()) { error in
            XCTAssertEqual(error as? ProvenanceError, .credentialUnavailable)
        }
    }

    func testFileCredentialProviderRejectsArbitraryPEM() throws {
        let directory = try makeTemporaryDirectory()
        let pem = directory.appendingPathComponent("arbitrary.pem")
        try Data("""
        -----BEGIN CERTIFICATE-----
        Zml4dHVyZQ==
        -----END CERTIFICATE-----
        -----BEGIN EC PRIVATE KEY-----
        Zml4dHVyZQ==
        -----END EC PRIVATE KEY-----
        """.utf8).write(to: pem)
        let provider = FileSigningCredentialProvider(
            credential: SigningCredential(certificateURL: pem, privateKeyURL: pem)
        )
        XCTAssertThrowsError(try provider.credential()) { error in
            XCTAssertEqual(error as? ProvenanceError, .credentialUnavailable)
        }
    }

    func testRuntimeExplicitBundleUsesOneExternalFileForCertAndKey() throws {
        let directory = try makeTemporaryDirectory()
        let tool = directory.appendingPathComponent("c2patool")
        let bundle = directory.appendingPathComponent("test-signing-bundle.pem")
        let root = directory.appendingPathComponent("root.pem")
        let config = directory.appendingPathComponent("store.cfg")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: tool.path
        )
        for file in [bundle, root, config] {
            try Data("fixture".utf8).write(to: file)
        }

        let runtime = try C2PARuntimeConfiguration.discover(environment: [
            "LOOP_GENERATOR_C2PATOOL": tool.path,
            "LOOP_GENERATOR_C2PA_SIGNING_BUNDLE": bundle.path,
            "LOOP_GENERATOR_C2PA_TRUST_ANCHORS": root.path,
            "LOOP_GENERATOR_C2PA_TRUST_CONFIG": config.path
        ])
        XCTAssertEqual(runtime.certificateURL, bundle)
        XCTAssertEqual(runtime.privateKeyURL, bundle)
    }

    func testValidationInspectionAcceptsFrozenProfileAndRejectsTamper() throws {
        let valid = try C2PAValidationInspection.inspect(
            validationReport(state: "Trusted", tampered: false)
        )
        XCTAssertTrue(valid.satisfiesV1Profile)
        XCTAssertTrue(valid.satisfiesV1Profile(
            applicationVersion: "0.2.0",
            modelName: "Stable Audio Open Small",
            modelVersion: "test-revision"
        ))
        XCTAssertFalse(valid.containsIngredients)
        XCTAssertFalse(valid.containsPromptOrSeed)
        XCTAssertFalse(valid.containsAllActionsIncluded)

        let tampered = try C2PAValidationInspection.inspect(
            validationReport(state: "Invalid", tampered: true)
        )
        XCTAssertTrue(tampered.detectsTampering)
        XCTAssertFalse(tampered.satisfiesV1Profile)
    }

    func testProvenanceServiceSignsValidatesReplacesAndStoresEvidence() async throws {
        let directory = try makeTemporaryDirectory()
        let credentialURL = directory.appendingPathComponent("external-bundle.pem")
        let exportedURL = directory.appendingPathComponent("export.wav")
        let evidenceURL = directory.appendingPathComponent("evidence", isDirectory: true)
        try Data("""
        -----BEGIN EC PRIVATE KEY-----
        Zml4dHVyZQ==
        -----END EC PRIVATE KEY-----
        """.utf8).write(to: credentialURL)
        try Data("unsigned".utf8).write(to: exportedURL)
        let record = makeRecord(outputAsset: exportedURL)
        let service = C2PAProvenanceService(
            manifestBuilder: C2PAManifestBuilder(applicationVersion: "0.2.0"),
            credentialProvider: FileSigningCredentialProvider(
                credential: SigningCredential(
                    certificateURL: credentialURL,
                    privateKeyURL: credentialURL
                ),
                expectedCertificateSHA256: nil
            ),
            toolRunner: SuccessfulMockC2PAToolRunner(
                report: validationReport(state: "Trusted", tampered: false)
            ),
            evidenceStore: JSONC2PAEvidenceStore(directoryURL: evidenceURL)
        )

        try await service.processExport(
            ExportContext(generationRecord: record, exportedAsset: exportedURL)
        )

        XCTAssertEqual(try Data(contentsOf: exportedURL), Data("signed".utf8))
        let recordEvidence = evidenceURL.appendingPathComponent(record.id.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: recordEvidence.appendingPathComponent("manifest.json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: recordEvidence.appendingPathComponent("validation.json").path
        ))
    }

    func testExportServicePropagatesProvenanceFailureAndRemovesPartialFile() async throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appendingPathComponent("export.wav")
        let service = ExportService(
            encoder: FixtureExportEncoder(),
            provenanceService: FailingProvenanceService()
        )

        do {
            try await service.exportWAV(record: makeRecord(), destination: destination)
            XCTFail("Expected C2PA validation failure")
        } catch {
            XCTAssertEqual(error as? ProvenanceError, .validationFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testLiveC2PASigningTrustAndTamperDetectionWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["LOOP_GENERATOR_C2PA_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set LOOP_GENERATOR_C2PA_LIVE_TEST=1 to run real C2PA signing")
        }
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("source.wav")
        let signed = directory.appendingPathComponent("signed.wav")
        let tampered = directory.appendingPathComponent("tampered.wav")
        let evidence = directory.appendingPathComponent("evidence", isDirectory: true)
        try makeStereoFixture(at: source)
        let record = makeRecord(outputAsset: source)
        let runtime = try C2PARuntimeConfiguration.discover()
        let provenance = try C2PAProvenanceService(
            applicationVersion: "0.2.0",
            runtime: runtime,
            evidenceStore: JSONC2PAEvidenceStore(directoryURL: evidence)
        )
        let exporter = ExportService(
            encoder: AVFoundationWAVEncoder(),
            provenanceService: provenance
        )

        try await exporter.exportWAV(record: record, destination: signed)
        let audio = try AVAudioFile(forReading: signed)
        XCTAssertEqual(audio.processingFormat.sampleRate, 44_100, accuracy: 0.1)
        XCTAssertEqual(audio.processingFormat.channelCount, 2)
        XCTAssertEqual(try wavBitsPerSample(at: signed), 24)

        let runner = C2PAToolRunner(configuration: runtime)
        let valid = try C2PAValidationInspection.inspect(
            try await runner.validate(asset: signed)
        )
        XCTAssertTrue(valid.satisfiesV1Profile(
            applicationVersion: "0.2.0",
            modelName: record.modelName,
            modelVersion: record.modelVersion
        ))

        var bytes = try Data(contentsOf: signed)
        bytes[1_000] ^= 1
        try bytes.write(to: tampered)
        let negative = try C2PAValidationInspection.inspect(
            try await runner.validate(asset: tampered)
        )
        XCTAssertTrue(negative.detectsTampering)
    }

    private func makeRecord(
        outputAsset: URL = URL(fileURLWithPath: "/tmp/source.wav")
    ) -> GenerationRecord {
        GenerationRecord(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            instrument: .synth,
            userPrompt: "private prompt that must not enter the manifest",
            finalPrompt: "Synth loop, private prompt that must not enter the manifest",
            durationSeconds: 4,
            seed: 424_242,
            modelName: "Stable Audio Open Small",
            modelVersion: "test-revision",
            generationTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            outputAsset: outputAsset
        )
    }

    private func validationReport(state: String, tampered: Bool) -> Data {
        let successes = tampered
            ? ["signingCredential.trusted", "claimSignature.validated"]
            : [
                "signingCredential.trusted",
                "claimSignature.validated",
                "assertion.dataHash.match"
            ]
        let failures = tampered ? ["assertion.dataHash.mismatch"] : []
        let report: [String: Any] = [
            "validation_state": state,
            "active_manifest": "urn:c2pa:test",
            "manifests": [
                "urn:c2pa:test": [
                    "claim": [
                        "claim_generator_info": [
                            "name": "Loop Generator",
                            "version": "0.2.0"
                        ]
                    ],
                    "assertion_store": [
                        "c2pa.actions.v2": [
                            "actions": [[
                                "action": "c2pa.created",
                                "digitalSourceType": C2PAManifestBuilder.digitalSourceType,
                                "softwareAgent": [
                                    "name": "Stable Audio Open Small",
                                    "version": "test-revision"
                                ],
                                "description": C2PAManifestBuilder.actionDescription
                            ]],
                        ],
                        "c2pa.hash.data": ["alg": "sha256"]
                    ]
                ]
            ],
            "validation_results": [
                "activeManifest": [
                    "success": successes.map { ["code": $0] },
                    "failure": failures.map { ["code": $0] }
                ]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: report)
    }

    private func recursivelyCollectedKeys(in value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, child in
                [key] + recursivelyCollectedKeys(in: child)
            }
        }
        if let array = value as? [Any] {
            return array.flatMap(recursivelyCollectedKeys)
        }
        return []
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
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
                buffer.floatChannelData![channel][frame] = Float(
                    sin(Double(frame) / 44_100 * 2 * Double.pi * 220) * 0.2
                )
            }
        }
        try file.write(from: buffer)
    }

    private func wavBitsPerSample(at url: URL) throws -> UInt16 {
        let data = try Data(contentsOf: url)
        let marker = Data("fmt ".utf8)
        let range = try XCTUnwrap(data.range(of: marker))
        let offset = range.lowerBound + 22
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
}

private struct SuccessfulMockC2PAToolRunner: C2PAToolRunning {
    let report: Data

    func sign(source: URL, manifest: URL, destination: URL) async throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path))
        try Data("signed".utf8).write(to: destination)
    }

    func validate(asset: URL) async throws -> Data {
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path))
        return report
    }
}

private struct FixtureExportEncoder: AudioExportEncoding {
    func encodeWAV(source: URL, destination: URL) throws {
        try Data("unsigned".utf8).write(to: destination)
    }
}

private struct FailingProvenanceService: ProvenanceService {
    func processExport(_ context: ExportContext) async throws {
        throw ProvenanceError.validationFailed
    }
}
