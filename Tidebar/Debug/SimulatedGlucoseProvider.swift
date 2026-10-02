//
//  SimulatedGlucoseProvider.swift
//  Tidebar
//

#if DEBUG
import Foundation

/// Stands in for the real provider while a Debug menu scenario is active, so the monitor,
/// staleness, and display logic run exactly as they would against real data.
nonisolated struct SimulatedGlucoseProvider: GlucoseProvider {
    /// Short delay so the "Updating…" status is visible, as with a real request.
    static let defaultSimulatedLatency: Duration = .milliseconds(400)

    let simulationScenario: DebugSimulationScenario
    var simulatedLatency: Duration = Self.defaultSimulatedLatency
    var currentDateProvider: @Sendable () -> Date = { Date() }

    var providerDisplayName: String {
        "Simulated: \(simulationScenario.displayName)"
    }

    func fetchLatestReading() async throws -> GlucoseReading {
        try await Task.sleep(for: simulatedLatency)
        guard let simulatedOutcome = simulationScenario.simulatedOutcome(at: currentDateProvider()) else {
            throw GlucoseProviderError.unexpectedResponse(description: "Live data is not simulated.")
        }
        return try simulatedOutcome.get()
    }

    func fetchRecentReadings(withinMinutes lookbackMinutes: Int) async throws -> [GlucoseReading] {
        [try await fetchLatestReading()]
    }
}
#endif
