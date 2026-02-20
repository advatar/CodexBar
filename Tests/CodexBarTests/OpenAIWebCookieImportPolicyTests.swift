import CodexBarCore
import Testing
@testable import CodexBar

@Suite
struct OpenAIWebCookieImportPolicyTests {
    @Test
    func backgroundImportRequiresCachedHeader() {
        #expect(
            UsageStore.shouldAttemptAutomaticOpenAICookieImport(
                interaction: .background,
                hasCachedCookieHeader: false) == false)
        #expect(
            UsageStore.shouldAttemptAutomaticOpenAICookieImport(
                interaction: .background,
                hasCachedCookieHeader: true) == true)
    }

    @Test
    func userInitiatedImportAlwaysAllowed() {
        #expect(
            UsageStore.shouldAttemptAutomaticOpenAICookieImport(
                interaction: .userInitiated,
                hasCachedCookieHeader: false) == true)
    }
}
