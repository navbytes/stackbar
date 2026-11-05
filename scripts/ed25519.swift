// Sparkle's EdDSA (Ed25519) key and signatures with Apple's CryptoKit, so
// the Release workflow needs no third-party crypto package.
//
//   swift scripts/ed25519.swift public-key      prints SUPublicEDKey
//   swift scripts/ed25519.swift sign <file>     prints sparkle:edSignature
//
// The private key comes from $SPARKLE_PRIVATE_KEY: a base64 Ed25519 seed
// (32 bytes; Sparkle's 64- and 96-byte exports start with the seed too).
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ed25519: \(message)\n".utf8))
    exit(1)
}

let encoded = (ProcessInfo.processInfo.environment["SPARKLE_PRIVATE_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
guard !encoded.isEmpty else { fail("SPARKLE_PRIVATE_KEY is not set") }
guard let raw = Data(base64Encoded: encoded), [32, 64, 96].contains(raw.count) else { fail("SPARKLE_PRIVATE_KEY is not a base64 Ed25519 seed") }
let key: Curve25519.Signing.PrivateKey
do { key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw.prefix(32)) } catch { fail("\(error)") }

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "public-key":
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard arguments.count == 2, let data = FileManager.default.contents(atPath: arguments[arguments.startIndex + 1]) else { fail("usage: sign <file>") }
    let signature = try key.signature(for: data)
    guard key.publicKey.isValidSignature(signature, for: data) else { fail("the signature doesn't verify") }
    print(signature.base64EncodedString())
default:
    fail("usage: public-key | sign <file>")
}
