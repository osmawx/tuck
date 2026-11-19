import CryptoKit
import Foundation

/// Derives the configured Sparkle public key without putting the private seed in arguments or logs.
func readPublicKey() throws -> String {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let encoded = String(decoding: input, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let seed = Data(base64Encoded: encoded), seed.count == 32 else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey.rawRepresentation.base64EncodedString()
}

do {
    print(try readPublicKey())
} catch {
    FileHandle.standardError.write(Data("Expected a 32-byte Sparkle seed in base64.\n".utf8))
    exit(1)
}
