import Foundation

public struct C2PARuntimeConfiguration: Equatable, Sendable {
    public static let c2paToolVersion = "0.27.15"
    public static let c2paSDKVersion = "0.90.15"
    public static let conformanceToolCommit = "44c81e07fc92b39a525412f4e7a1c2cda0757beb"

    public let toolURL: URL
    public let certificateURL: URL
    public let privateKeyURL: URL
    public let trustAnchorsURL: URL
    public let trustConfigURL: URL

    public init(
        toolURL: URL,
        certificateURL: URL,
        privateKeyURL: URL,
        trustAnchorsURL: URL,
        trustConfigURL: URL
    ) {
        self.toolURL = toolURL
        self.certificateURL = certificateURL
        self.privateKeyURL = privateKeyURL
        self.trustAnchorsURL = trustAnchorsURL
        self.trustConfigURL = trustConfigURL
    }

    public static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws -> C2PARuntimeConfiguration {
        if let explicit = explicitConfiguration(
            environment: environment,
            fileManager: fileManager
        ) {
            return explicit
        }

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("LoopGenerator/c2pa", isDirectory: true)

        let toolCandidates = [
            bundle.resourceURL?.appendingPathComponent("c2pa/c2patool"),
            applicationSupport.appendingPathComponent("c2patool"),
            sourceRoot.appendingPathComponent(
                ".tooling/c2pa/\(c2paToolVersion)/c2patool/c2patool"
            )
        ].compactMap { $0 }
        let signingBundleCandidates = [
            fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first?
                .appendingPathComponent("test-signing-bundle.pem")
        ].compactMap { $0 }
        let trustRoots = [
            bundle.resourceURL?.appendingPathComponent("c2pa/trust", isDirectory: true),
            applicationSupport.appendingPathComponent("trust", isDirectory: true),
            sourceRoot.appendingPathComponent(".c2pa-test/trust", isDirectory: true)
        ].compactMap { $0 }

        guard let toolURL = toolCandidates.first(where: {
            fileManager.isExecutableFile(atPath: $0.path)
        }) else {
            throw ProvenanceError.toolUnavailable
        }
        guard let signingBundleURL = signingBundleCandidates.first(where: {
            fileManager.isReadableFile(atPath: $0.path)
        }) else {
            throw ProvenanceError.credentialUnavailable
        }
        guard let trustRoot = trustRoots.first(where: {
            containsTrustFiles(at: $0, fileManager: fileManager)
        }) else {
            throw ProvenanceError.validationFailed
        }

        return C2PARuntimeConfiguration(
            toolURL: toolURL,
            certificateURL: signingBundleURL,
            privateKeyURL: signingBundleURL,
            trustAnchorsURL: trustRoot.appendingPathComponent("test-root-cert.pem"),
            trustConfigURL: trustRoot.appendingPathComponent("store.cfg")
        )
    }

    private static func explicitConfiguration(
        environment: [String: String],
        fileManager: FileManager
    ) -> C2PARuntimeConfiguration? {
        guard let toolPath = environment["LOOP_GENERATOR_C2PATOOL"],
              let trustAnchorsPath = environment["LOOP_GENERATOR_C2PA_TRUST_ANCHORS"],
              let trustConfigPath = environment["LOOP_GENERATOR_C2PA_TRUST_CONFIG"] else {
            return nil
        }
        let certificatePath: String
        let privateKeyPath: String
        if let signingBundlePath = environment["LOOP_GENERATOR_C2PA_SIGNING_BUNDLE"] {
            certificatePath = signingBundlePath
            privateKeyPath = signingBundlePath
        } else if let signCertificatePath = environment["LOOP_GENERATOR_C2PA_SIGN_CERT"],
                  let signingKeyPath = environment["LOOP_GENERATOR_C2PA_PRIVATE_KEY"] {
            certificatePath = signCertificatePath
            privateKeyPath = signingKeyPath
        } else {
            return nil
        }

        let configuration = C2PARuntimeConfiguration(
            toolURL: URL(fileURLWithPath: toolPath),
            certificateURL: URL(fileURLWithPath: certificatePath),
            privateKeyURL: URL(fileURLWithPath: privateKeyPath),
            trustAnchorsURL: URL(fileURLWithPath: trustAnchorsPath),
            trustConfigURL: URL(fileURLWithPath: trustConfigPath)
        )
        guard fileManager.isExecutableFile(atPath: configuration.toolURL.path),
              fileManager.isReadableFile(atPath: configuration.certificateURL.path),
              fileManager.isReadableFile(atPath: configuration.privateKeyURL.path),
              fileManager.isReadableFile(atPath: configuration.trustAnchorsURL.path),
              fileManager.isReadableFile(atPath: configuration.trustConfigURL.path) else {
            return nil
        }
        return configuration
    }

    private static func containsTrustFiles(
        at root: URL,
        fileManager: FileManager
    ) -> Bool {
        let paths = [
            "test-root-cert.pem",
            "store.cfg"
        ]
        return paths.allSatisfy {
            fileManager.isReadableFile(atPath: root.appendingPathComponent($0).path)
        }
    }
}
