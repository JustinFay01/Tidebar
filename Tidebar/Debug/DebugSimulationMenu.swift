//
//  DebugSimulationMenu.swift
//  Tidebar
//

#if DEBUG
import SwiftUI

/// Debug-build-only submenu for simulating provider errors and reading states.
struct DebugSimulationMenu: View {
    let debugSimulationController: DebugSimulationController
    let glucoseMonitor: GlucoseMonitor

    var body: some View {
        Menu("Debug") {
            Picker("Simulate", selection: selectedScenarioBinding) {
                Text(DebugSimulationScenario.liveData.displayName)
                    .tag(DebugSimulationScenario.liveData)
                Section("Errors") {
                    scenarioOptions(DebugSimulationScenario.errorScenarios)
                }
                Section("Readings") {
                    scenarioOptions(DebugSimulationScenario.readingScenarios)
                }
            }
            .pickerStyle(.inline)
        }
    }

    private var selectedScenarioBinding: Binding<DebugSimulationScenario> {
        Binding(
            get: { debugSimulationController.activeScenario },
            set: { selectedScenario in
                debugSimulationController.selectScenario(selectedScenario, glucoseMonitor: glucoseMonitor)
            }
        )
    }

    private func scenarioOptions(_ simulationScenarios: [DebugSimulationScenario]) -> some View {
        ForEach(simulationScenarios) { simulationScenario in
            Text(simulationScenario.displayName).tag(simulationScenario)
        }
    }
}
#endif
