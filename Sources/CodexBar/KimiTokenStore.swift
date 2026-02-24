import CodexBarCore
import Foundation
import Security

protocol KimiTokenStoring: Sendable {
    func loadToken() throws -> String?
    func storeToken(_ token: String?) throws
}

enum KimiTokenStoreError: LocalizedError {
    case keychainStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case let .keychainStatus(status):
            "Keychain error: \(status)"
        case .invalidData:
            "Keychain returned invalid data."
        }
    }
}

struct KeychainKimiTokenStore: KimiTokenStoring {
    private static let log = CodexBarLog.logger(LogCategories.kimiTokenStore)

    private let service = "com.steipete.CodexBar"
    private let account = "kimi-auth-token"

    // Cache/cooldown to reduce repeated keychain prompts during refresh loops.
    private nonisolated(unsafe) static var cachedToken: String?
    private nonisolated(unsafe) static var cacheTimestamp: Date?
    private nonisolated(unsafe) static var deniedUntil: Date?
    private static let cacheLock = NSLock()
    private static let cacheTTL: TimeInterval = 1800 // 30 minutes
    private static let promptCooldown: TimeInterval = 60 * 60 * 6 // 6 hours

    func loadToken() throws -> String? {
        guard !KeychainAccessGate.isDisabled else {
            Self.log.debug("Keychain access disabled; skipping token load")
            return nil
        }
        let now = Date()
        Self.cacheLock.lock()
        if let timestamp = Self.cacheTimestamp,
           now.timeIntervalSince(timestamp) < Self.cacheTTL
        {
            let cached = Self.cachedToken
            Self.cacheLock.unlock()
            Self.log.debug("Using cached Kimi token")
            return cached
        }
        if let deniedUntil = Self.deniedUntil {
            if deniedUntil > now {
                Self.cacheLock.unlock()
                Self.log.debug("Skipping Kimi keychain read during prompt cooldown")
                return nil
            }
            Self.deniedUntil = nil
        }
        Self.cacheLock.unlock()

        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        if case .interactionRequired = KeychainAccessPreflight
            .checkGenericPassword(service: self.service, account: self.account)
        {
            KeychainPromptHandler.handler?(KeychainPromptContext(
                kind: .kimiToken,
                service: self.service,
                account: self.account))
        }

        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            Self.cache(token: nil, now: now)
            return nil
        }
        if Self.isPromptDeniedStatus(status) {
            Self.recordDenied(now: now)
            Self.cache(token: nil, now: now)
            Self.log.info("Kimi keychain access denied; suppressing prompts during cooldown")
            return nil
        }
        guard status == errSecSuccess else {
            Self.log.error("Keychain read failed: \(status)")
            throw KimiTokenStoreError.keychainStatus(status)
        }

        guard let data = result as? Data else {
            throw KimiTokenStoreError.invalidData
        }
        let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalToken = token?.isEmpty == false ? token : nil
        Self.cache(token: finalToken, now: now)
        return finalToken
    }

    func storeToken(_ token: String?) throws {
        guard !KeychainAccessGate.isDisabled else {
            Self.log.debug("Keychain access disabled; skipping token store")
            return
        }
        let cleaned = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned == nil || cleaned?.isEmpty == true {
            try self.deleteTokenIfPresent()
            return
        }

        let data = cleaned!.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            Self.cache(token: cleaned, now: Date())
            Self.clearDenied()
            return
        }
        if updateStatus != errSecItemNotFound {
            Self.log.error("Keychain update failed: \(updateStatus)")
            throw KimiTokenStoreError.keychainStatus(updateStatus)
        }

        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            Self.log.error("Keychain add failed: \(addStatus)")
            throw KimiTokenStoreError.keychainStatus(addStatus)
        }
        Self.cache(token: cleaned, now: Date())
        Self.clearDenied()
    }

    private func deleteTokenIfPresent() throws {
        guard !KeychainAccessGate.isDisabled else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            Self.cache(token: nil, now: Date())
            Self.clearDenied()
            return
        }
        Self.log.error("Keychain delete failed: \(status)")
        throw KimiTokenStoreError.keychainStatus(status)
    }

    private static func cache(token: String?, now: Date) {
        self.cacheLock.lock()
        self.cachedToken = token
        self.cacheTimestamp = now
        self.cacheLock.unlock()
    }

    private static func recordDenied(now: Date) {
        self.cacheLock.lock()
        self.deniedUntil = now.addingTimeInterval(self.promptCooldown)
        self.cacheLock.unlock()
    }

    private static func clearDenied() {
        self.cacheLock.lock()
        self.deniedUntil = nil
        self.cacheLock.unlock()
    }

    private static func isPromptDeniedStatus(_ status: OSStatus) -> Bool {
        status == errSecUserCanceled
            || status == errSecAuthFailed
            || status == errSecInteractionNotAllowed
            || status == errSecNoAccessForItem
    }
}
