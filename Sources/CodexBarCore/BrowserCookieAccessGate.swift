import Foundation

#if os(macOS)
import os.lock
import SweetCookieKit

public enum BrowserCookieAccessGate {
    private struct State {
        var loaded = false
        var deniedUntilByBrowser: [String: Date] = [:]
        var attemptedAtByBrowser: [String: Date] = [:]
    }

    private static let lock = OSAllocatedUnfairLock<State>(initialState: State())
    private static let deniedDefaultsKey = "browserCookieAccessDeniedUntil"
    private static let attemptedDefaultsKey = "browserCookieAccessAttemptedAt"
    private static let denyCooldownInterval: TimeInterval = 60 * 60 * 6
    private static let attemptCooldownInterval: TimeInterval = 60 * 30
    private static let log = CodexBarLog.logger(LogCategories.browserCookieGate)

    public static func shouldAttempt(_ browser: Browser, now: Date = Date()) -> Bool {
        guard browser.usesKeychainForCookieDecryption else { return true }
        guard !KeychainAccessGate.isDisabled else { return false }
        return self.lock.withLock { state in
            self.loadIfNeeded(&state)
            if let blockedUntil = state.deniedUntilByBrowser[browser.rawValue] {
                if blockedUntil > now {
                    self.log.debug(
                        "Cookie access blocked",
                        metadata: ["browser": browser.displayName, "until": "\(blockedUntil.timeIntervalSince1970)"])
                    return false
                }
                state.deniedUntilByBrowser.removeValue(forKey: browser.rawValue)
                self.persist(state)
            }
            if let attemptedAt = state.attemptedAtByBrowser[browser.rawValue],
               now.timeIntervalSince(attemptedAt) < self.attemptCooldownInterval
            {
                let nextAttempt = attemptedAt.addingTimeInterval(self.attemptCooldownInterval)
                self.log.debug(
                    "Cookie access attempt throttled",
                    metadata: [
                        "browser": browser.displayName,
                        "until": "\(nextAttempt.timeIntervalSince1970)",
                    ])
                return false
            }
            if self.browserKeychainRequiresInteraction(browser) {
                let blockedUntil = now.addingTimeInterval(self.denyCooldownInterval)
                state.deniedUntilByBrowser[browser.rawValue] = blockedUntil
                state.attemptedAtByBrowser[browser.rawValue] = now
                self.persist(state)
                self.log.info(
                    "Cookie access requires keychain interaction; suppressing",
                    metadata: [
                        "browser": browser.displayName,
                        "until": "\(blockedUntil.timeIntervalSince1970)",
                    ])
                return false
            }
            let nextAttempt = now.addingTimeInterval(self.attemptCooldownInterval)
            state.attemptedAtByBrowser[browser.rawValue] = now
            self.persist(state)
            self.log.debug(
                "Cookie access allowed",
                metadata: [
                    "browser": browser.displayName,
                    "nextAttemptAt": "\(nextAttempt.timeIntervalSince1970)",
                ])
            return true
        }
    }

    public static func recordIfNeeded(_ error: Error, now: Date = Date()) {
        guard let error = error as? BrowserCookieError else { return }
        guard case .accessDenied = error else { return }
        self.recordDenied(for: error.browser, now: now)
    }

    public static func recordDenied(for browser: Browser, now: Date = Date()) {
        guard browser.usesKeychainForCookieDecryption else { return }
        let blockedUntil = now.addingTimeInterval(self.denyCooldownInterval)
        self.lock.withLock { state in
            self.loadIfNeeded(&state)
            state.deniedUntilByBrowser[browser.rawValue] = blockedUntil
            state.attemptedAtByBrowser[browser.rawValue] = now
            self.persist(state)
        }
        self.log
            .info(
                "Browser cookie access denied; suppressing prompts",
                metadata: [
                    "browser": browser.displayName,
                    "until": "\(blockedUntil.timeIntervalSince1970)",
                ])
    }

    public static func resetForTesting() {
        self.lock.withLock { state in
            state.loaded = true
            state.deniedUntilByBrowser.removeAll()
            state.attemptedAtByBrowser.removeAll()
            UserDefaults.standard.removeObject(forKey: self.deniedDefaultsKey)
            UserDefaults.standard.removeObject(forKey: self.attemptedDefaultsKey)
        }
    }

    private static func browserKeychainRequiresInteraction(_ browser: Browser) -> Bool {
        let labels = self.safeStorageLabels(for: browser)
        guard !labels.isEmpty else { return false }
        for label in labels {
            switch KeychainAccessPreflight.checkGenericPassword(service: label.service, account: label.account) {
            case .allowed:
                return false
            case .interactionRequired:
                return true
            case .notFound, .failure:
                continue
            }
        }
        return false
    }

    private static func safeStorageLabels(for browser: Browser) -> [(service: String, account: String)] {
        let direct = browser.safeStorageLabels
        if !direct.isEmpty { return direct }
        switch browser {
        case .chromeBeta, .chromeCanary:
            return Browser.chrome.safeStorageLabels
        case .braveBeta, .braveNightly:
            return Browser.brave.safeStorageLabels
        case .edgeBeta, .edgeCanary:
            return Browser.edge.safeStorageLabels
        default:
            return []
        }
    }

    private static func loadIfNeeded(_ state: inout State) {
        guard !state.loaded else { return }
        state.loaded = true
        if let deniedRaw = UserDefaults.standard.dictionary(forKey: self.deniedDefaultsKey) as? [String: Double] {
            state.deniedUntilByBrowser = deniedRaw.compactMapValues { Date(timeIntervalSince1970: $0) }
        }
        if let attemptedRaw = UserDefaults.standard.dictionary(forKey: self.attemptedDefaultsKey) as? [String: Double] {
            state.attemptedAtByBrowser = attemptedRaw.compactMapValues { Date(timeIntervalSince1970: $0) }
        }
    }

    private static func persist(_ state: State) {
        let deniedRaw = state.deniedUntilByBrowser.mapValues { $0.timeIntervalSince1970 }
        if deniedRaw.isEmpty {
            UserDefaults.standard.removeObject(forKey: self.deniedDefaultsKey)
        } else {
            UserDefaults.standard.set(deniedRaw, forKey: self.deniedDefaultsKey)
        }
        let attemptedRaw = state.attemptedAtByBrowser.mapValues { $0.timeIntervalSince1970 }
        if attemptedRaw.isEmpty {
            UserDefaults.standard.removeObject(forKey: self.attemptedDefaultsKey)
        } else {
            UserDefaults.standard.set(attemptedRaw, forKey: self.attemptedDefaultsKey)
        }
    }
}
#else
public enum BrowserCookieAccessGate {
    public static func shouldAttempt(_ browser: Browser, now: Date = Date()) -> Bool {
        true
    }

    public static func recordIfNeeded(_ error: Error, now: Date = Date()) {}
    public static func recordDenied(for browser: Browser, now: Date = Date()) {}
    public static func resetForTesting() {}
}
#endif
