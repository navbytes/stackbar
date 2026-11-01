import Foundation

extension Stackbar {
    /// How a request proves who it is, from a secret the manifest declares
    /// with `.secret(name:)`. Pass it as `auth:` to `getJSON`, `postJSON`,
    /// `get` or `http`, and the secret is read and checked for you.
    public enum Auth: Equatable, Sendable {
        /// `Authorization: Bearer <secret>`, as GitHub and most APIs take it.
        case bearer(secret: String)
        /// The secret in any header, after `prefix` and a space when there
        /// is one: Linear takes a bare `.header("Authorization", secret:
        /// "LINEAR_API_KEY")`, DeepL `prefix: "DeepL-Auth-Key"`.
        case header(String, secret: String, prefix: String = "")

        /// The header to add. An unset or empty secret throws
        /// `StackbarError.missingSecret`.
        func header() async throws -> (name: String, value: String) {
            let (name, secret, prefix) = switch self {
            case .bearer(let secret): ("Authorization", secret, "Bearer")
            case .header(let name, let secret, let prefix): (name, secret, prefix)
            }
            guard let value = try await Stackbar.secret(secret), !value.isEmpty else {
                throw StackbarError.missingSecret(secret)
            }
            return (name, prefix.isEmpty ? value : "\(prefix) \(value)")
        }
    }
}

/// Errors from the kit's own helpers that a plugin may want to tell apart
/// from a failed host call (`HostError`).
public enum StackbarError: Error, Equatable, CustomStringConvertible, Sendable {
    /// The user hasn't entered this secret yet. The host is already asking
    /// for it at the top of the panel and refreshes the plugin once it is
    /// saved, so show `ContentUnavailableView(error)` meanwhile.
    case missingSecret(String)

    public var description: String {
        switch self {
        case .missingSecret(let name): "\(name) is not set yet"
        }
    }
}
