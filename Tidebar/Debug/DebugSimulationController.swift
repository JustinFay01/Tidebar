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
    @ObservationIgnored private var hasReturnedSetupFailureForActiveScenario = false

    func selectScenario(_ selectedScenario: DebugSimulationScenario, glucoseMonitor: GlucoseMonitor) {
        guard selectedScenario != activeScenario else {
            return
        }
        activeScenario = selectedScenario
        hasReturnedSetupFailureForActiveScenario = false
        glucoseMonitor.rebuildProviderAndRefresh()
    }

    /// The provider, or setup failure, to use instead of the real one; `nil` when showing live data.
    func makeSimulatedProviderSetupResultIfActive() -> Result<any GlucoseProvider, GlucoseProviderSetupError>? {
        guard activeScenario != .liveData else {
            return nil
        }
        guard let simulatedSetupError = activeScenario.simulatedSetupError else {
            return .success(SimulatedGlucoseProvider(simulationScenario: activeScenario))
        }
        // Fails once, then hands back to live data so the monitor's own retry is what recovers.
        if activeScenario == .keychainUnreadableUntilRetry, hasReturnedSetupFailureForActiveScenario {
            activeScenario = .liveData
            return nil
        }
        hasReturnedSetupFailureForActiveScenario = true
        return .failure(simulatedSetupError)
    }
}
#endif
