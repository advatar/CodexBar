import CodexBarCore
import Foundation
import Security

protocol TeamDeviceTokenStoring: Sendable {
    func loadToken(deviceID: String) throws -> String?
    func storeToken(_ token: String?, deviceID: String) throws
}

enum TeamDeviceTokenStoreError: LocalizedError {
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

struct KeychainTeamDeviceTokenStore: TeamDeviceTokenStoring {
    private static let log = CodexBarLog.logger(LogCategories.teamTokenStore)

    private let service = "com.steipete.CodexBar"
    private let accountPrefix = "com.codexbar.team.deviceToken."

    private struct CachedToken {
        let value: String?
        let timestamp: Date

        var isExpired: Bool {
            Date().timeIntervalSince(self.timestamp) > KeychainTeamDeviceTokenStore.cacheTTL
        }
    }

    private nonisolated(unsafe) static var cache: [String: CachedToken] = [:]
    private nonisolated(unsafe) static var deniedUntilByAccount: [String: Date] = [:]
    private static let cacheLock = NSLock()
    private static let cacheTTL: TimeInterval = 1800 // 30 minutes
    private static let promptCooldown: TimeInterval = 60 * 60 * 6 // 6 hours

    func loadToken(deviceID: String) throws -> String? {
        guard !KeychainAccessGate.isDisabled else {
            Self.log.debug("Keychain access disabled; skipping team token load")
            return nil
        }
        let account = self.account(for: deviceID)
        let now = Date()

        Self.cacheLock.lock()
        if let cached = Self.cache[account], !cached.isExpired {
            Self.cacheLock.unlock()
            Self.log.debug("Using cached team token for \(account)")
            return cached.value
        }
        if let deniedUntil = Self.deniedUntilByAccount[account] {
            if deniedUntil > now {
                Self.cacheLock.unlock()
                Self.log.debug("Skipping team token keychain read during prompt cooldown for \(account)")
                return nil
            }
            Self.deniedUntilByAccount.removeValue(forKey: account)
        }
        Self.cacheLock.unlock()

        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        if case .interactionRequired = KeychainAccessPreflight
            .checkGenericPassword(service: self.service, account: account)
        {
            KeychainPromptHandler.handler?(KeychainPromptContext(
                kind: .teamDeviceToken,
                service: self.service,
                account: account))
        }

        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            Self.cache(token: nil, account: account, now: now)
            return nil
        }
        if Self.isPromptDeniedStatus(status) {
            Self.recordDenied(account: account, now: now)
            Self.cache(token: nil, account: account, now: now)
            Self.log.info("Team token keychain access denied; suppressing prompts during cooldown")
            return nil
        }
        guard status == errSecSuccess else {
            Self.log.error("Team token keychain read failed: \(status)")
            throw TeamDeviceTokenStoreError.keychainStatus(status)
        }
        guard let data = result as? Data else {
            throw TeamDeviceTokenStoreError.invalidData
        }
        let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalToken = token?.isEmpty == false ? token : nil
        Self.cache(token: finalToken, account: account, now: now)
        return finalToken
    }

    func storeToken(_ token: String?, deviceID: String) throws {
        guard !KeychainAccessGate.isDisabled else {
            Self.log.debug("Keychain access disabled; skipping team token store")
            return
        }
        let cleanedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = self.account(for: deviceID)
        if cleanedToken == nil || cleanedToken?.isEmpty == true {
            try self.deleteTokenIfPresent(account: account)
            return
        }

        let data = cleanedToken!.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            Self.cache(token: cleanedToken, account: account, now: Date())
            Self.clearDenied(account: account)
            return
        }
        if updateStatus != errSecItemNotFound {
            Self.log.error("Team token keychain update failed: \(updateStatus)")
            throw TeamDeviceTokenStoreError.keychainStatus(updateStatus)
        }

        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            Self.log.error("Team token keychain add failed: \(addStatus)")
            throw TeamDeviceTokenStoreError.keychainStatus(addStatus)
        }
        Self.cache(token: cleanedToken, account: account, now: Date())
        Self.clearDenied(account: account)
    }

    private func deleteTokenIfPresent(account: String) throws {
        guard !KeychainAccessGate.isDisabled else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            Self.cache(token: nil, account: account, now: Date())
            Self.clearDenied(account: account)
            return
        }
        Self.log.error("Team token keychain delete failed: \(status)")
        throw TeamDeviceTokenStoreError.keychainStatus(status)
    }

    private func account(for deviceID: String) -> String {
        self.accountPrefix + deviceID
    }

    private static func cache(token: String?, account: String, now: Date) {
        self.cacheLock.lock()
        self.cache[account] = CachedToken(value: token, timestamp: now)
        self.cacheLock.unlock()
    }

    private static func recordDenied(account: String, now: Date) {
        self.cacheLock.lock()
        self.deniedUntilByAccount[account] = now.addingTimeInterval(self.promptCooldown)
        self.cacheLock.unlock()
    }

    private static func clearDenied(account: String) {
        self.cacheLock.lock()
        self.deniedUntilByAccount.removeValue(forKey: account)
        self.cacheLock.unlock()
    }

    private static func isPromptDeniedStatus(_ status: OSStatus) -> Bool {
        status == errSecUserCanceled
            || status == errSecAuthFailed
            || status == errSecInteractionNotAllowed
            || status == errSecNoAccessForItem
    }
}
