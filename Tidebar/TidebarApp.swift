//
//  TidebarApp.swift
//  Tidebar
//
//  Created by Justin Fay on 10/2/26.
//

import SwiftUI

@main
struct TidebarApp: App {
    @State private var glucoseMonitor: GlucoseMonitor
    @State private var diagnosticsReporter: DiagnosticsReporter
    #if DEBUG
    @State private var debugSimulationController: DebugSimulationController
    #endif

    init() {
        let diagnosticEventLog = DiagnosticEventLog()
        #if DEBUG
        let debugSimulationController = DebugSimulationController()
        _debugSimulationController = State(initialValue: debugSimulationController)
        let glucoseMonitor = GlucoseMonitor(
            providerBuilder: {
                if let simulatedProvider = debugSimulationController.makeSimulatedProviderIfActive() {
                    return .success(simulatedProvider)
                }
                return Self.buildProviderFromSavedSettings(diagnosticEventLog: diagnosticEventLog)
            },
            diagnosticEventRecorder: diagnosticEventLog
        )
        #else
        let glucoseMonitor = GlucoseMonitor(
            providerBuilder: { Self.buildProviderFromSavedSettings(diagnosticEventLog: diagnosticEventLog) },
            diagnosticEventRecorder: diagnosticEventLog
        )
        #endif
        if !Self.isRunningUnitTests {
            glucoseMonitor.start()
        }
        _glucoseMonitor = State(initialValue: glucoseMonitor)
        _diagnosticsReporter = State(
            initialValue: DiagnosticsReporter(glucoseMonitor: glucoseMonitor, diagnosticEventLog: diagnosticEventLog)
        )
    }

    var body: some Scene {
        MenuBarExtra {
            menuBarContent
        } label: {
            MenuBarLabelView(glucoseMonitor: glucoseMonitor)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(glucoseMonitor: glucoseMonitor)
        }
    }

    private var menuBarContent: some View {
        #if DEBUG
        MenuBarContentView(
            glucoseMonitor: glucoseMonitor,
            diagnosticsReporter: diagnosticsReporter,
            debugSimulationController: debugSimulationController
        )
        #else
        MenuBarContentView(glucoseMonitor: glucoseMonitor, diagnosticsReporter: diagnosticsReporter)
        #endif
    }

    private static func buildProviderFromSavedSettings(
        diagnosticEventLog: DiagnosticEventLog
    ) -> Result<any GlucoseProvider, GlucoseProviderSetupError> {
        do {
            return .success(try GlucoseProviderFactory.makeGlucoseProviderFromSavedSettings(diagnosticEventRecorder: diagnosticEventLog))
        } catch {
            return .failure(error)
        }
    }

    /// The test bundle is hosted in the app; don't poll Dexcom or touch the Keychain while tests run.
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
