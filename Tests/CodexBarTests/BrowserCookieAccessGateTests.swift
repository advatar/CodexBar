import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
import SweetCookieKit

@Suite(.serialized)
struct BrowserCookieAccessGateTests {
    @Test
    func throttlesRepeatedAllowedAttemptsForSameBrowser() {
        BrowserCookieAccessGate.resetForTesting()

        let preflight: (String, String?) -> KeychainAccessPreflight.Outcome = { _, _ in
            .allowed
        }

        KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting(preflight) {
            let start = Date(timeIntervalSince1970: 1_000_000)
            #expect(BrowserCookieAccessGate.shouldAttempt(.chrome, now: start))
            #expect(BrowserCookieAccessGate.shouldAttempt(.chrome, now: start.addingTimeInterval(60)) == false)
            #expect(BrowserCookieAccessGate.shouldAttempt(.chrome, now: start.addingTimeInterval(31 * 60)))
        }
    }

    @Test
    func preflightsPerBrowserInsteadOfGlobalKeychainPool() {
        BrowserCookieAccessGate.resetForTesting()

        let preflight: (String, String?) -> KeychainAccessPreflight.Outcome = { service, _ in
            service.contains("Chrome") ? .interactionRequired : .allowed
        }

        KeychainAccessPreflight.withCheckGenericPasswordOverrideForTesting(preflight) {
            let now = Date(timeIntervalSince1970: 2_000_000)
            #expect(BrowserCookieAccessGate.shouldAttempt(.chrome, now: now) == false)
            #expect(BrowserCookieAccessGate.shouldAttempt(.edge, now: now))
        }
    }
}
#endif
