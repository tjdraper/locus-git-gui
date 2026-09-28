import Foundation
import Security

/// The trial's start in the Keychain, which keeps it when the app is deleted and installed again.
/// It's the data protection keychain, shared by every build signed by the same team, so a Debug
/// build reads what a release build wrote without macOS asking for a password.
nonisolated struct TrialStartKeychain: Sendable {
    enum Reading: Equatable {
        case found(Date)
        case notFound
        case failed(OSStatus)
    }

    private static let service = "com.buzzingpixel.LocusGitGui.Trial"
    private static let account = "TrialStart"

    func read() -> Reading {
        var query = Self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let seconds = String(data: data, encoding: .utf8).flatMap(TimeInterval.init)
            else { return .failed(errSecDecode) }
            return .found(Date(timeIntervalSinceReferenceDate: seconds))
        case errSecItemNotFound:
            return .notFound
        default:
            return .failed(status)
        }
    }

    /// The status of the write, `errSecSuccess` when it worked.
    @discardableResult
    func write(_ start: Date) -> OSStatus {
        // Swift writes a Double with as many digits as it takes to read back the same value, so the
        // start compares equal to the one iCloud has.
        let data = Data(String(start.timeIntervalSinceReferenceDate).utf8)
        let update = SecItemUpdate(Self.query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard update == errSecItemNotFound else { return update }
        var item = Self.query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecAttrLabel as String] = "Locus Git Gui trial"
        return SecItemAdd(item as CFDictionary, nil)
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
