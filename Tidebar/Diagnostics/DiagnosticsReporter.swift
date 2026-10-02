//
//  DiagnosticsReporter.swift
//  Tidebar
//

import AppKit
import Foundation

/// Gathers a diagnostics report and hands it to the user: to the clipboard, or into a GitHub issue
/// the user reviews and submits themselves. Nothing is ever sent automatically.
@MainActor
final class DiagnosticsReporter {
    static let issueRepositoryURLString = "https://github.com/JustinFay01/Tidebar/issues/new"
    static let bugReportTemplateFileName = "bug_report.yml"

    private let glucoseMonitor: GlucoseMonitor
    private let diagnosticEventLog: DiagnosticEventLog
    private let userDefaults: UserDefaults

    init(glucoseMonitor: GlucoseMonitor, diagnosticEventLog: DiagnosticEventLog, userDefaults: UserDefaults = .standard) {
        self.glucoseMonitor = glucoseMonitor
        self.diagnosticEventLog = diagnosticEventLog
        self.userDefaults = userDefaults
    }

    func buildReportText() -> String {
        DiagnosticsReportBuilder.buildReport(
            from: DiagnosticsReportInput(
                reportGeneratedDate: Date(),
                environment: Self.currentEnvironment(),
                settingsSummary: currentSettingsSummary(),
                monitorStatus: glucoseMonitor.diagnosticsStatus,
                recentEvents: diagnosticEventLog.recentEvents
            )
        )
    }

    func copyReportToPasteboard() {
        let generalPasteboard = NSPasteboard.general
        generalPasteboard.clearContents()
        generalPasteboard.setString(buildReportText(), forType: .string)
    }

    /// Explains what will happen, then copies the report and opens a pre-filled GitHub issue form.
    func reportProblem() {
        NSApplication.shared.activate()
        guard confirmReportingWithUser() else {
            return
        }
        copyReportToPasteboard()
        if let bugReportURL = Self.makeBugReportURL(diagnosticCode: glucoseMonitor.currentDiagnosticCode) {
            NSWorkspace.shared.open(bugReportURL)
        }
    }

    /// The issue form's title is pre-filled with the current problem code, if any. The report itself
    /// is pasted by the user rather than put in the URL, which keeps it reviewable and avoids URL length limits.
    static func makeBugReportURL(diagnosticCode: TidebarDiagnosticCode?) -> URL? {
        guard var urlComponents = URLComponents(string: issueRepositoryURLString) else {
            return nil
        }
        var queryItems = [URLQueryItem(name: "template", value: bugReportTemplateFileName)]
        if let diagnosticCode {
            queryItems.append(URLQueryItem(name: "title", value: "[\(diagnosticCode.rawValue)] "))
        }
        urlComponents.queryItems = queryItems
        return urlComponents.url
    }

    private func confirmReportingWithUser() -> Bool {
        let confirmationAlert = NSAlert()
        confirmationAlert.messageText = "Report a Problem"
        confirmationAlert.informativeText = """
            Tidebar will copy a diagnostics report to your clipboard and open a new GitHub issue in your browser.

            Paste the report into the Diagnostics field and review it before submitting. \
            \(DiagnosticsReportBuilder.privacyNote)
            """
        confirmationAlert.addButton(withTitle: "Copy Report & Open GitHub")
        confirmationAlert.addButton(withTitle: "Cancel")
        return confirmationAlert.runModal() == .alertFirstButtonReturn
    }

    private func currentSettingsSummary() -> DiagnosticsSettingsSummary {
        let savedConfiguration = GlucoseProviderConfiguration.loadSavedConfiguration(from: userDefaults)
        let savedRegion: DexcomShareRegion? =
            switch savedConfiguration {
            case .dexcomShare(_, let region): region
            case nil: nil
            }
        let savedUnit = userDefaults.string(forKey: AppSettingsKeys.glucoseUnit).flatMap(GlucoseUnit.init(rawValue:))
        return DiagnosticsSettingsSummary(
            isAccountConfigured: savedConfiguration != nil,
            dexcomRegion: savedRegion,
            glucoseUnit: savedUnit ?? .milligramsPerDeciliter,
            isLaunchAtLoginEnabled: LaunchAtLoginController.isRegisteredWithSystem
        )
    }

    private static func currentEnvironment() -> DiagnosticsEnvironment {
        let bundleInfo = Bundle.main.infoDictionary ?? [:]
        return DiagnosticsEnvironment(
            appVersion: bundleInfo["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuildNumber: bundleInfo["CFBundleVersion"] as? String ?? "unknown",
            buildConfiguration: currentBuildConfiguration,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hardwareArchitecture: currentHardwareArchitecture
        )
    }

    private static var currentBuildConfiguration: String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }

    private static var currentHardwareArchitecture: String {
        #if arch(arm64)
        "Apple silicon"
        #elseif arch(x86_64)
        "Intel"
        #else
        "unknown architecture"
        #endif
    }
}
