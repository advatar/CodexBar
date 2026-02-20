import AppKit
import CodexBarCore
import SwiftUI

@MainActor
struct TeamPane: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore

    @State private var inviteCode: String = ""
    @State private var serverURLText: String = ""
    @State private var isJoining = false
    @State private var isSendingTest = false
    @State private var actionMessage: String?

    var body: some View {
        let teamSettings = self.settings.teamReportingSettings

        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(contentSpacing: 12) {
                    Text("Reporting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    PreferenceToggleRow(
                        title: "Enable Team Reporting",
                        subtitle: "When enabled, TeamTokenBar sends anonymized usage snapshots to your team backend.",
                        binding: self.teamBinding(\.enabled))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server URL")
                            .font(.body)
                        HStack(spacing: 8) {
                            TextField("https://ukuxfyfawzdiddzogpeu.supabase.co", text: self.$serverURLText)
                                .textFieldStyle(.roundedBorder)
                            Button("Apply") {
                                _ = self.applyServerURL()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Invite Code")
                            .font(.body)
                        TextField("CBT-XXXXXX-XXXX", text: self.$inviteCode)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Device Label")
                            .font(.body)
                        TextField("My Mac", text: self.teamBinding(\.deviceLabel))
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Text("Report Interval")
                            .font(.body)
                        Spacer()
                        Picker("Report Interval", selection: self.teamBinding(\.reportInterval)) {
                            ForEach(TeamReportInterval.allCases) { interval in
                                Text(interval.label).tag(interval)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 180)
                    }
                }

                Divider()

                SettingsSection(contentSpacing: 10) {
                    HStack(spacing: 8) {
                        Button {
                            Task { await self.joinTeam() }
                        } label: {
                            if self.isJoining {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Join Team")
                            }
                        }
                        .disabled(self.isJoining || self.inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty)

                        Button {
                            Task { await self.sendTestReport() }
                        } label: {
                            if self.isSendingTest {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Send Test Report Now")
                            }
                        }
                        .disabled(self.isSendingTest || !teamSettings.isJoined)

                        Button("Leave Team") {
                            self.settings.leaveTeam()
                            self.actionMessage = "Team membership removed."
                        }
                        .disabled(!teamSettings.isJoined)
                    }

                    HStack(spacing: 8) {
                        Button("Open Dashboard") {
                            self.openDashboard()
                        }
                        .disabled(self.settings.teamDashboardURL() == nil)

                        if self.settings.teamClaimURL() != nil {
                            Button("Open Claim Page") {
                                self.openClaimPage()
                            }
                            .disabled(!teamSettings.isJoined)
                        }
                    }

                    if let actionMessage, !actionMessage.isEmpty {
                        Text(actionMessage)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                SettingsSection(contentSpacing: 8) {
                    Text("Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    self.statusRow("Joined Team", teamSettings.teamName ?? "Not joined")

                    HStack(spacing: 8) {
                        self.statusRow("Member ID", teamSettings.memberPublicId ?? "—")
                        if let memberID = teamSettings.memberPublicId, !memberID.isEmpty {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(memberID, forType: .string)
                                self.actionMessage = "Member ID copied."
                            }
                            .buttonStyle(.link)
                        }
                    }

                    self.statusRow("Device ID", teamSettings.deviceId ?? "—")
                    self.statusRow("Token", teamSettings.tokenLast4.map { "••••\($0)" } ?? "Not stored")
                    self.statusRow("Last Report", self.lastReportText(from: teamSettings.lastReportAt))
                    self.statusRow("Last Result", self.resultText(teamSettings.lastReportResult))

                    if let error = teamSettings.lastReportErrorMessage, !error.isEmpty {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let claimCode = teamSettings.claimCode, !claimCode.isEmpty {
                        self.statusRow("Claim Code", claimCode)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear {
            if self.serverURLText.isEmpty {
                self.serverURLText = teamSettings.serverBaseURL.absoluteString
            }
        }
        .onChange(of: self.settings.teamReportingSettings.serverBaseURL.absoluteString) { _, newValue in
            self.serverURLText = newValue
        }
    }
}

extension TeamPane {
    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.body)
            Spacer()
            Text(value)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func teamBinding<T>(_ keyPath: WritableKeyPath<TeamReportingSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings.teamReportingSettings[keyPath: keyPath] },
            set: { newValue in
                self.settings.updateTeamReportingSettings { settings in
                    settings[keyPath: keyPath] = newValue
                }
            })
    }

    @discardableResult
    private func applyServerURL() -> Bool {
        let trimmed = self.serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.actionMessage = "Server URL cannot be empty."
            return false
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              scheme == "https" || scheme == "http"
        else {
            self.actionMessage = "Enter a valid http/https URL."
            return false
        }

        self.settings.updateTeamReportingSettings { settings in
            settings.serverBaseURL = url
        }
        return true
    }

    private func joinTeam() async {
        guard self.applyServerURL() else { return }
        if self.isJoining { return }
        self.isJoining = true
        defer { self.isJoining = false }

        do {
            let result = try await self.settings.joinTeam(inviteCode: self.inviteCode)
            self.inviteCode = ""
            self.actionMessage = "Joined \(result.teamName) as \(result.memberPublicID)."
        } catch {
            self.actionMessage = error.localizedDescription
        }
    }

    private func sendTestReport() async {
        guard self.applyServerURL() else { return }
        if self.isSendingTest { return }
        self.isSendingTest = true
        defer { self.isSendingTest = false }

        await self.store.sendTeamReportNow()
        let teamSettings = self.settings.teamReportingSettings
        switch teamSettings.lastReportResult {
        case .ok:
            self.actionMessage = "Test report sent."
        case .throttled, .authFailed, .serverError, .networkError:
            self.actionMessage = teamSettings.lastReportErrorMessage ?? "Test report failed."
        case nil:
            self.actionMessage = "No report was sent."
        }
    }

    private func openDashboard() {
        guard let url = self.settings.teamDashboardURL() else { return }
        NSWorkspace.shared.open(url)
    }

    private func openClaimPage() {
        guard let url = self.settings.teamClaimURL() else { return }
        NSWorkspace.shared.open(url)
    }

    private func lastReportText(from date: Date?) -> String {
        guard let date else { return "Never" }
        return UsageFormatter.updatedString(from: date)
    }

    private func resultText(_ result: TeamReportResult?) -> String {
        switch result {
        case .ok: "OK"
        case .throttled: "Throttled"
        case .authFailed: "Auth failed"
        case .serverError: "Server error"
        case .networkError: "Network error"
        case .none: "—"
        }
    }
}
