import CryptoKit
import Foundation

public struct SigningCredential: Equatable, Sendable {
    public let certificateURL: URL
    public let privateKeyURL: URL
    public let algorithm: String

    public init(
        certificateURL: URL,
        privateKeyURL: URL,
        algorithm: String = "es256"
    ) {
        self.certificateURL = certificateURL
        self.privateKeyURL = privateKeyURL
        self.algorithm = algorithm
    }
}

public protocol SigningCredentialProvider: Sendable {
    func credential() throws -> SigningCredential
}

public struct FileSigningCredentialProvider: SigningCredentialProvider, @unchecked Sendable {
    public static let conformanceTestCertificateSHA256 =
        "b27c27d45019dc80d4755a26207b9e02e236e54d70928573d68e4ece18068755"

    private let credentialValue: SigningCredential
    private let expectedCertificateSHA256: String?
    private let fileManager: FileManager

    public init(
        credential: SigningCredential,
        expectedCertificateSHA256: String? = Self.conformanceTestCertificateSHA256,
        fileManager: FileManager = .default
    ) {
        credentialValue = credential
        self.expectedCertificateSHA256 = expectedCertificateSHA256
        self.fileManager = fileManager
    }

    public func credential() throws -> SigningCredential {
        guard fileManager.isReadableFile(atPath: credentialValue.certificateURL.path),
              fileManager.isReadableFile(atPath: credentialValue.privateKeyURL.path) else {
            throw ProvenanceError.credentialUnavailable
        }
        guard let keyPEM = try? String(
            contentsOf: credentialValue.privateKeyURL,
            encoding: .utf8
        ), keyPEM.contains("-----BEGIN EC PRIVATE KEY-----")
            || keyPEM.contains("-----BEGIN PRIVATE KEY-----") else {
            throw ProvenanceError.credentialUnavailable
        }
        if let expectedCertificateSHA256 {
            guard let certificateData = try? Data(contentsOf: credentialValue.certificateURL),
                  let certificateDER = certificateDER(in: certificateData),
                  sha256(certificateDER) == expectedCertificateSHA256.lowercased() else {
                throw ProvenanceError.credentialUnavailable
            }
        }
        return credentialValue
    }

    private func certificateDER(in pemData: Data) -> Data? {
        guard let pem = String(data: pemData, encoding: .utf8),
              let begin = pem.range(of: "-----BEGIN CERTIFICATE-----"),
              let end = pem.range(
                  of: "-----END CERTIFICATE-----",
                  range: begin.upperBound..<pem.endIndex
              ) else {
            return nil
        }
        let base64 = String(pem[begin.upperBound..<end.lowerBound])
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
