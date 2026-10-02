//
//  DebugSimulationController.swift
//  Tidebar
//

#if DEBUG
import Foundation
import Observation

/// Holds the scenario chosen in the Debug menu. Kept in memory only, so every launch starts on live data.
@MainActor
@Observable
final class DebugSimulationController {
    private(set) var activeScenario = DebugSimulationScenario.liveData

    func selectScenario(_ selectedScenario: DebugSimulationScenario, glucoseMonitor: GlucoseMonitor) {
        guard selectedScenario != activeScenario else {
            return
        }
        activeScenario = selectedScenario
        glucoseMonitor.rebuildProviderAndRefresh()
    }

    /// The provider to use instead of the real one, or `nil` when showing live data.
    func makeSimulatedProviderIfActive() -> (any GlucoseProvider)? {
        guard activeScenario != .liveData else {
            return nil
        }
        return SimulatedGlucoseProvider(simulationScenario: activeScenario)
    }
}
#endif
