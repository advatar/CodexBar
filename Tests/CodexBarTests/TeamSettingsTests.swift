import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite
struct TeamSettingsTests {
    @Test
    func teamReportingDefaultsToDisabled() {
        let settings = Self.makeSettingsStore(suite: "TeamSettingsTests-defaults")
        let team = settings.teamReportingSettings

        #expect(team.enabled == false)
        #expect(team.teamId == nil)
        #expect(team.serverBaseURL == TeamAPIConstants.defaultServerBaseURL)
    }

    @Test
    func teamReportingPersistsAcrossInstances() throws {
        let suite = "TeamSettingsTests-persist"
        let settingsA = Self.makeSettingsStore(suite: suite)
        var updated = settingsA.teamReportingSettings
        updated.serverBaseURL = try #require(URL(string: "https://team.example.com"))
        updated.enabled = true
        updated.teamId = "team_123"
        updated.teamName = "Infra Team"
        updated.memberPublicId = "mbr_7K2P9D"
        updated.deviceId = "device_abc"
        updated.deviceLabel = "Build Mac"
        updated.reportInterval = .fifteenMinutes
        settingsA.teamReportingSettings = updated

        let settingsB = Self.makeSettingsStore(suite: suite, reset: false)
        let restored = settingsB.teamReportingSettings

        #expect(restored.serverBaseURL.absoluteString == "https://team.example.com")
        #expect(restored.enabled == true)
        #expect(restored.teamId == "team_123")
        #expect(restored.memberPublicId == "mbr_7K2P9D")
        #expect(restored.deviceLabel == "Build Mac")
        #expect(restored.reportInterval == .fifteenMinutes)
    }

    @Test
    func joinTeamStoresMembershipAndToken() async throws {
        let suite = "TeamSettingsTests-join"
        let tokenStore = InMemoryTeamDeviceTokenStore()
        let responseJSON = """
        {
          "team": { "id": "team_123", "name": "Platform Team" },
          "member": { "public_id": "mbr_7K2P9D" },
          "device": {
            "id": "device_abc",
            "device_label": "Alice MacBook",
            "platform": "macos",
            "app_version": "1.2.3"
          },
          "reporting": {
            "token": "tok_1234567890",
            "recommended_interval_seconds": 300
          },
          "claim": {
            "claim_code": "claim_abc",
            "expires_at": "2026-03-01T00:00:00Z",
            "claim_page": "/claim"
          }
        }
        """
        let client = TeamAPIClient(dataLoader: { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://ukuxfyfawzdiddzogpeu.supabase.co/functions/v1/redeem_invite")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)!
            return (Data(responseJSON.utf8), response)
        })
        let settings = Self.makeSettingsStore(
            suite: suite,
            teamDeviceTokenStore: tokenStore,
            teamAPIClient: client)

        let result = try await settings.joinTeam(inviteCode: "CBT-AAAAAA-1111")
        let team = settings.teamReportingSettings

        #expect(result.teamName == "Platform Team")
        #expect(team.enabled == true)
        #expect(team.teamId == "team_123")
        #expect(team.teamName == "Platform Team")
        #expect(team.memberPublicId == "mbr_7K2P9D")
        #expect(team.deviceId == "device_abc")
        #expect(team.tokenLast4 == "7890")
        #expect(team.reportInterval == .fiveMinutes)
        #expect(try tokenStore.loadToken(deviceID: "device_abc") == "tok_1234567890")
    }

    @Test
    func joinTeamAcceptsTopLevelDeviceToken() async throws {
        let suite = "TeamSettingsTests-join-device-token"
        let tokenStore = InMemoryTeamDeviceTokenStore()
        let responseJSON = """
        {
          "team": { "id": "team_999", "name": "Ops Team" },
          "member": { "public_id": "mbr_ABC123" },
          "device": {
            "id": "device_xyz",
            "device_label": "CI Mac mini",
            "platform": "macos",
            "app_version": "1.2.3"
          },
          "device_token": "tok_top_level_9999"
        }
        """
        let client = TeamAPIClient(dataLoader: { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://ukuxfyfawzdiddzogpeu.supabase.co/functions/v1/redeem_invite")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)!
            return (Data(responseJSON.utf8), response)
        })
        let settings = Self.makeSettingsStore(
            suite: suite,
            teamDeviceTokenStore: tokenStore,
            teamAPIClient: client)

        _ = try await settings.joinTeam(inviteCode: "CBT-BBBBBB-2222")
        let team = settings.teamReportingSettings

        #expect(team.teamId == "team_999")
        #expect(team.deviceId == "device_xyz")
        #expect(team.tokenLast4 == "9999")
        #expect(team.reportInterval == .automatic)
        #expect(try tokenStore.loadToken(deviceID: "device_xyz") == "tok_top_level_9999")
    }

    @Test
    func leaveTeamClearsMembershipAndToken() throws {
        let suite = "TeamSettingsTests-leave"
        let tokenStore = InMemoryTeamDeviceTokenStore()
        let settings = Self.makeSettingsStore(suite: suite, teamDeviceTokenStore: tokenStore)

        var team = settings.teamReportingSettings
        team.enabled = true
        team.teamId = "team_123"
        team.deviceId = "device_abc"
        settings.teamReportingSettings = team
        try tokenStore.storeToken("tok_abc", deviceID: "device_abc")

        settings.leaveTeam()
        let cleared = settings.teamReportingSettings

        #expect(cleared.enabled == false)
        #expect(cleared.teamId == nil)
        #expect(cleared.deviceId == nil)
        #expect(try tokenStore.loadToken(deviceID: "device_abc") == nil)
    }
}

extension TeamSettingsTests {
    fileprivate static func makeSettingsStore(
        suite: String,
        reset: Bool = true,
        teamDeviceTokenStore: any TeamDeviceTokenStoring = InMemoryTeamDeviceTokenStore(),
        teamAPIClient: TeamAPIClient = TeamAPIClient()) -> SettingsStore
    {
        let defaults = UserDefaults(suiteName: suite)!
        if reset {
            defaults.removePersistentDomain(forName: suite)
        }
        let configStore = testConfigStore(suiteName: suite, reset: reset)

        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            kimiK2TokenStore: InMemoryKimiK2TokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore(),
            teamDeviceTokenStore: teamDeviceTokenStore,
            teamAPIClient: teamAPIClient)
    }
}
