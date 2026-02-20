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

    func loadToken(deviceID: String) throws -> String? {
        guard !KeychainAccessGate.isDisabled else {
            Self.log.debug("Keychain access disabled; skipping team token load")
            return nil
        }
        let account = self.account(for: deviceID)
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
        if let token, !token.isEmpty {
            return token
        }
        return nil
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
            return
        }
        Self.log.error("Team token keychain delete failed: \(status)")
        throw TeamDeviceTokenStoreError.keychainStatus(status)
    }

    private func account(for deviceID: String) -> String {
        self.accountPrefix + deviceID
    }
}
