//
//  MenuBarContentView.swift
//  Tidebar
//

import AppKit
import SwiftUI

/// The dropdown menu: latest reading details, source, status, and actions.
struct MenuBarContentView: View {
    let glucoseMonitor: GlucoseMonitor
    let diagnosticsReporter: DiagnosticsReporter
    #if DEBUG
    let debugSimulationController: DebugSimulationController
    #endif

    @AppStorage(AppSettingsKeys.glucoseUnit) private var glucoseUnit = GlucoseUnit.milligramsPerDeciliter
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(readingSummaryText)
        Text(lastReadingText)
        Text(sourceText)
        Text(statusText)

        Divider()

        Button("Refresh Now") {
            glucoseMonitor.refreshNow()
        }
        .keyboardShortcut("r")
        .disabled(glucoseMonitor.providerSetupError != nil)

        Button("Settings…") {
            openSettingsInForeground()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Copy Diagnostics") {
            diagnosticsReporter.copyReportToPasteboard()
        }

        Button("Report a Problem…") {
            diagnosticsReporter.reportProblem()
        }

        #if DEBUG
        Divider()

        DebugSimulationMenu(debugSimulationController: debugSimulationController, glucoseMonitor: glucoseMonitor)
        #endif

        Divider()

        Button("Quit Tidebar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var readingSummaryText: String {
        guard let latestReading = glucoseMonitor.latestReading else {
            return "No reading yet"
        }
        let formattedValue = glucoseUnit.formattedValue(fromMgPerDeciliter: latestReading.valueMgPerDeciliter)
        let trendSymbol = GlucoseStatusFormatter.trendSymbol(for: latestReading.trendDirection)
        return "\(formattedValue) \(glucoseUnit.unitLabel) \(trendSymbol)  \(latestReading.trendDirection.trendDescription)"
    }

    private var lastReadingText: String {
        guard let latestReading = glucoseMonitor.latestReading else {
            return "Last reading: none"
        }
        let relativeAge = GlucoseStatusFormatter.relativeAgeDescription(
            of: latestReading,
            currentDate: glucoseMonitor.displayEvaluationDate
        )
        let clockTime = latestReading.readingTimestamp.formatted(date: .omitted, time: .shortened)
        return "Last reading: \(relativeAge) (\(clockTime))"
    }

    private var sourceText: String {
        "Source: \(glucoseMonitor.providerDisplayName ?? "Not configured")"
    }

    private var statusText: String {
        if glucoseMonitor.isFetchInProgress {
            return "Status: Updating…"
        }
        switch glucoseMonitor.displayState {
        case .unknown(let reason):
            return "Status: \(reason)"
        case .current:
            return "Status: Up to date"
        case .aging:
            return "Status: Waiting for a new reading"
        }
    }

    /// Menu bar apps are not frontmost, so the Settings window would open behind other apps.
    /// Plain `activate()` is only a request the system can decline, so force activation and raise the window.
    private func openSettingsInForeground() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
        // The window is created or shown after this action returns.
        DispatchQueue.main.async {
            for settingsWindow in NSApplication.shared.windows where Self.isSettingsWindow(settingsWindow) {
                settingsWindow.makeKeyAndOrderFront(nil)
                settingsWindow.orderFrontRegardless()
            }
        }
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == settingsWindowIdentifier
    }

    /// The identifier SwiftUI gives the `Settings` scene's window.
    private static let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"
}
