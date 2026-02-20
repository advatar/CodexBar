import CodexBarCore
import Foundation

enum UsagePaceText {
    struct WeeklyDetail: Sendable {
        let leftLabel: String
        let rightLabel: String?
        let expectedUsedPercent: Double
        let stage: UsagePace.Stage
    }

    private static let minimumExpectedPercent: Double = 3

    static func weeklySummary(provider: UsageProvider, window: RateWindow, now: Date = .init()) -> String? {
        guard let detail = weeklyDetail(provider: provider, window: window, now: now) else { return nil }
        if let rightLabel = detail.rightLabel {
            return "Pace: \(detail.leftLabel) · \(rightLabel)"
        }
        return "Pace: \(detail.leftLabel)"
    }

    static func weeklyDetail(provider: UsageProvider, window: RateWindow, now: Date = .init()) -> WeeklyDetail? {
        guard let pace = weeklyPace(provider: provider, window: window, now: now) else { return nil }
        return WeeklyDetail(
            leftLabel: Self.detailLeftLabel(for: pace),
            rightLabel: Self.detailRightLabel(for: pace, window: window, now: now),
            expectedUsedPercent: pace.expectedUsedPercent,
            stage: pace.stage)
    }

    private static func detailLeftLabel(for pace: UsagePace) -> String {
        let deltaValue = Int(abs(pace.deltaPercent).rounded())
        switch pace.stage {
        case .onTrack:
            return "On pace"
        case .slightlyAhead, .ahead, .farAhead:
            return "\(deltaValue)% in deficit"
        case .slightlyBehind, .behind, .farBehind:
            return "\(deltaValue)% in reserve"
        }
    }

    private static func detailRightLabel(for pace: UsagePace, window: RateWindow, now: Date) -> String? {
        if pace.willLastToReset { return "Lasts until reset" }
        guard let etaSeconds = pace.etaSeconds else { return nil }
        let etaText = Self.durationText(seconds: etaSeconds, now: now)
        let runsOutLabel = if etaText == "now" { "Runs out now" } else { "Runs out in \(etaText)" }
        guard Self.isDeficitStage(pace.stage), let resetsAt = window.resetsAt else { return runsOutLabel }
        let refreshLabel = Self.refreshCountdownLabel(resetAt: resetsAt, now: now)
        guard let withoutLabel = Self.withoutAccessLabel(etaSeconds: etaSeconds, resetAt: resetsAt, now: now) else {
            return "\(runsOutLabel) · \(refreshLabel)"
        }
        return "\(runsOutLabel) · \(refreshLabel) · \(withoutLabel)"
    }

    private static func isDeficitStage(_ stage: UsagePace.Stage) -> Bool {
        switch stage {
        case .slightlyAhead, .ahead, .farAhead:
            true
        case .onTrack, .slightlyBehind, .behind, .farBehind:
            false
        }
    }

    private static func refreshCountdownLabel(resetAt: Date, now: Date) -> String {
        let text = Self.durationText(seconds: resetAt.timeIntervalSince(now), now: now)
        if text == "now" { return "refresh now" }
        return "refresh in \(text)"
    }

    private static func withoutAccessLabel(etaSeconds: TimeInterval, resetAt: Date, now: Date) -> String? {
        let runOutAt = now.addingTimeInterval(etaSeconds)
        let deficitSeconds = resetAt.timeIntervalSince(runOutAt)
        guard deficitSeconds > 0 else { return nil }
        return "without for \(Self.dayHourText(seconds: deficitSeconds))"
    }

    private static func dayHourText(seconds: TimeInterval) -> String {
        let totalHours = max(1, Int((seconds / 3600).rounded(.up)))
        let days = totalHours / 24
        let hours = totalHours % 24
        return "\(days)d \(hours)h"
    }

    private static func durationText(seconds: TimeInterval, now: Date) -> String {
        let date = now.addingTimeInterval(seconds)
        let countdown = UsageFormatter.resetCountdownDescription(from: date, now: now)
        if countdown == "now" { return "now" }
        if countdown.hasPrefix("in ") { return String(countdown.dropFirst(3)) }
        return countdown
    }

    static func weeklyPace(provider: UsageProvider, window: RateWindow, now: Date) -> UsagePace? {
        guard provider == .codex || provider == .claude else { return nil }
        guard window.remainingPercent > 0 else { return nil }
        guard let pace = UsagePace.weekly(window: window, now: now, defaultWindowMinutes: 10080) else { return nil }
        guard pace.expectedUsedPercent >= Self.minimumExpectedPercent else { return nil }
        return pace
    }
}
