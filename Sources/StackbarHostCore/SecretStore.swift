import Foundation
#if canImport(Security)
import Security
#endif

/// Where the host keeps secrets and OAuth tokens. Plugins never see this
/// store; they get single values through `Stackbar.secret` after a capability
/// check.
public protocol SecretStore: Sendable {
    func secret(_ name: String) throws -> String?
    func setSecret(_ value: String?, for name: String) throws
}

/// In memory, for tests and one-off runs.
public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    public init(_ values: [String: String] = [:]) { self.values = values }

    public func secret(_ name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[name]
    }

    public func setSecret(_ value: String?, for name: String) {
        lock.lock()
        values[name] = value
        lock.unlock()
    }
}

/// A JSON file readable only by the user (0600). For Linux and `stackbarctl`,
/// where there is no Keychain.
public final class FileSecretStore: SecretStore, @unchecked Sendable {
    public let file: URL
    private let lock = NSLock()

    public init(file: URL) { self.file = file }

    public func secret(_ name: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return try load()[name]
    }

    public func setSecret(_ value: String?, for name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var values = try load()
        values[name] = value
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func load() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
    }
}

/// Reads secrets from environment variables and never writes. Chained after a
/// real store, it lets `GITHUB_TOKEN=… stackbarctl render` work in a terminal.
public struct EnvironmentSecretStore: SecretStore {
    public var environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func secret(_ name: String) -> String? { environment[name] }
    public func setSecret(_ value: String?, for name: String) throws {
        throw SecretStoreError.readOnly
    }
}

/// Reads from the first store that has the secret; writes to the first store.
public struct ChainedSecretStore: SecretStore {
    public var stores: [any SecretStore]

    public init(_ stores: [any SecretStore]) { self.stores = stores }

    public func secret(_ name: String) throws -> String? {
        for store in stores {
            if let value = try store.secret(name) { return value }
        }
        return nil
    }

    public func setSecret(_ value: String?, for name: String) throws {
        guard let first = stores.first else { throw SecretStoreError.readOnly }
        try first.setSecret(value, for: name)
    }
}

public enum SecretStoreError: Error, CustomStringConvertible {
    case readOnly
    case keychain(Int32)

    public var description: String {
        switch self {
        case .readOnly: return "this secret store is read-only"
        case .keychain(let status): return "Keychain error \(status)"
        }
    }
}

#if canImport(Security)
/// The login Keychain, as generic passwords under one service name.
public struct KeychainSecretStore: SecretStore {
    public var service: String

    public init(service: String = "io.navbytes.stackbar.secrets") { self.service = service }

    public func secret(_ name: String) throws -> String? {
        var query = baseQuery(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw SecretStoreError.keychain(status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func setSecret(_ value: String?, for name: String) throws {
        let query = baseQuery(name)
        guard let value else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.keychain(status) }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw SecretStoreError.keychain(added) }
        } else if status != errSecSuccess {
            throw SecretStoreError.keychain(status)
        }
    }

    private func baseQuery(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: name]
    }
}
#endif
