import Foundation

public protocol C2PAToolRunning: Sendable {
    func sign(source: URL, manifest: URL, destination: URL) async throws
    func validate(asset: URL) async throws -> Data
}

public struct C2PAToolRunner: C2PAToolRunning, Sendable {
    public let configuration: C2PARuntimeConfiguration

    public init(configuration: C2PARuntimeConfiguration) {
        self.configuration = configuration
    }

    public func sign(source: URL, manifest: URL, destination: URL) async throws {
        let result = try await run(arguments: [
            source.path,
            "--manifest", manifest.path,
            "--create", "trainedAlgorithmicMedia",
            "--output", destination.path
        ])
        guard result.status == 0,
              FileManager.default.fileExists(atPath: destination.path) else {
            throw ProvenanceError.signingFailed
        }
    }

    public func validate(asset: URL) async throws -> Data {
        let result = try await run(arguments: [
            asset.path,
            "--detailed",
            "trust",
            "--trust_anchors", configuration.trustAnchorsURL.path,
            "--trust_config", configuration.trustConfigURL.path
        ])
        guard result.status == 0, !result.standardOutput.isEmpty else {
            throw ProvenanceError.validationFailed
        }
        return result.standardOutput
    }

    private func run(arguments: [String]) async throws -> ProcessResult {
        let toolURL = configuration.toolURL
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            process.executableURL = toolURL
            process.arguments = arguments
            process.standardOutput = standardOutput
            process.standardError = standardError

            do {
                try process.run()
            } catch {
                throw ProvenanceError.toolUnavailable
            }
            let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return ProcessResult(
                status: process.terminationStatus,
                standardOutput: outputData,
                standardError: errorData
            )
        }.value
    }
}

private struct ProcessResult: Sendable {
    let status: Int32
    let standardOutput: Data
    let standardError: Data
}
