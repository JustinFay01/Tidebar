//
//  DiagnosticsReport.swift
//  Tidebar
//

import Foundation

/// Monitor state for a diagnostics report. Contains no glucose values or reading timestamps.
nonisolated struct GlucoseMonitorDiagnosticsStatus: Equatable, Sendable {
    enum DisplayStateKind: String, Sendable {
        case current
        case aging
        case unknown

        init(_ displayState: GlucoseDisplayState) {
            switch displayState {
            case .current: self = .current
            case .aging: self = .aging
            case .unknown: self = .unknown
            }
        }
    }

    let displayStateKind: DisplayStateKind
    let currentDiagnosticCode: TidebarDiagnosticCode?
    let providerDisplayName: String?
    let latestReadingAgeSeconds: Int?
    let secondsSinceLastSuccessfulFetch: Int?
    let consecutiveFetchFailureCount: Int
    let isFetchInProgress: Bool
}

nonisolated struct DiagnosticsEnvironment: Equatable, Sendable {
    let appVersion: String
    let appBuildNumber: String
    let buildConfiguration: String
    let operatingSystemVersion: String
    let hardwareArchitecture: String
}

/// Non-secret settings worth including in a report. Never add the username or password.
nonisolated struct DiagnosticsSettingsSummary: Equatable, Sendable {
    let isAccountConfigured: Bool
    let dexcomRegion: DexcomShareRegion?
    let glucoseUnit: GlucoseUnit
    let isLaunchAtLoginEnabled: Bool
}

nonisolated struct DiagnosticsReportInput: Sendable {
    let reportGeneratedDate: Date
    let environment: DiagnosticsEnvironment
    let settingsSummary: DiagnosticsSettingsSummary
    let monitorStatus: GlucoseMonitorDiagnosticsStatus
    let recentEvents: [DiagnosticEvent]
}

/// Builds the plain-text report users copy or paste into a GitHub issue.
nonisolated enum DiagnosticsReportBuilder {
    static let reportTitle = "Tidebar Diagnostics"
    static let privacyNote =
        "This report never includes your username, password, account or session IDs, or glucose readings."

    static func buildReport(from reportInput: DiagnosticsReportInput) -> String {
        var reportLines = [
            reportTitle,
            privacyNote,
            "",
            "Generated: \(formatTimestamp(reportInput.reportGeneratedDate))",
        ]
        reportLines += environmentLines(for: reportInput.environment)
        reportLines += [""] + settingsLines(for: reportInput.settingsSummary)
        reportLines += [""] + statusLines(for: reportInput.monitorStatus)
        reportLines += [""] + recentActivityLines(for: reportInput.recentEvents)
        return reportLines.joined(separator: "\n") + "\n"
    }

    private static func environmentLines(for environment: DiagnosticsEnvironment) -> [String] {
        [
            "Tidebar: \(environment.appVersion) (\(environment.appBuildNumber)), \(environment.buildConfiguration)",
            "macOS: \(environment.operatingSystemVersion) (\(environment.hardwareArchitecture))",
        ]
    }

    private static func settingsLines(for settingsSummary: DiagnosticsSettingsSummary) -> [String] {
        [
            "Settings",
            "  Account configured: \(yesOrNo(settingsSummary.isAccountConfigured))",
            "  Region: \(settingsSummary.dexcomRegion?.rawValue ?? "not set")",
            "  Unit: \(settingsSummary.glucoseUnit.unitLabel)",
            "  Launch at login: \(yesOrNo(settingsSummary.isLaunchAtLoginEnabled))",
        ]
    }

    private static func statusLines(for monitorStatus: GlucoseMonitorDiagnosticsStatus) -> [String] {
        let problemDescription =
            monitorStatus.currentDiagnosticCode.map { "\($0.rawValue): \($0.summary)" } ?? "none"
        return [
            "Status",
            "  Display: \(monitorStatus.displayStateKind.rawValue)",
            "  Problem: \(problemDescription)",
            "  Provider: \(monitorStatus.providerDisplayName ?? "not configured")",
            "  Latest reading age: \(formatOptionalAge(monitorStatus.latestReadingAgeSeconds))",
            "  Last successful fetch: \(formatOptionalAge(monitorStatus.secondsSinceLastSuccessfulFetch, suffix: " ago"))",
            "  Consecutive failures: \(monitorStatus.consecutiveFetchFailureCount)",
            "  Fetch in progress: \(yesOrNo(monitorStatus.isFetchInProgress))",
        ]
    }

    private static func recentActivityLines(for recentEvents: [DiagnosticEvent]) -> [String] {
        guard !recentEvents.isEmpty else {
            return ["Recent activity: none"]
        }
        let eventLines = recentEvents.map { diagnosticEvent in
            "  \(formatTimestamp(diagnosticEvent.eventTimestamp))  \(DiagnosticEventDescriber.describe(diagnosticEvent.eventKind))"
        }
        return ["Recent activity (oldest first, \(recentEvents.count) events)"] + eventLines
    }

    /// UTC and locale-independent, e.g. `2026-10-02T22:00:01Z`.
    static func formatTimestamp(_ timestamp: Date) -> String {
        timestamp.formatted(.iso8601)
    }

    private static func formatOptionalAge(_ ageSeconds: Int?, suffix: String = "") -> String {
        guard let ageSeconds else {
            return "none"
        }
        return DiagnosticEventDescriber.formatSeconds(ageSeconds) + suffix
    }

    private static func yesOrNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }
}
