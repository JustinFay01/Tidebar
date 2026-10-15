//
//  SimulatedGlucoseProvider.swift
//  Tidebar
//

#if DEBUG
import Foundation
import os

/// Stands in for the real provider while a Debug menu scenario is active, so the monitor,
/// staleness, and display logic run exactly as they would against real data.
nonisolated struct SimulatedGlucoseProvider: GlucoseProvider {
    /// Short delay so the "Updating…" status is visible, as with a real request.
    static let defaultSimulatedLatency: Duration = .milliseconds(400)

    let simulationScenario: DebugSimulationScenario
    var simulatedLatency: Duration = Self.defaultSimulatedLatency
    var currentDateProvider: @Sendable () -> Date = { Date() }
    /// Lets reading scenarios answer their first fetch with an earlier reading, and keep a single reading's
    /// timestamp across fetches. A new provider is built whenever a scenario is chosen, so each choice
    /// starts again from the first fetch.
    let lockedFetchHistory = OSAllocatedUnfairLock(initialState: SimulatedFetchHistory())

    var providerDisplayName: String {
        "Simulated: \(simulationScenario.displayName)"
    }

    func fetchLatestReading() async throws -> GlucoseReading {
        try await Task.sleep(for: simulatedLatency)
        let currentDate = currentDateProvider()
        let (fetchIndex, firstFetchDate) = lockedFetchHistory.withLock { fetchHistory in
            defer { fetchHistory.answeredFetchCount += 1 }
            let firstFetchDate = fetchHistory.firstFetchDate ?? currentDate
            fetchHistory.firstFetchDate = firstFetchDate
            return (fetchHistory.answeredFetchCount, firstFetchDate)
        }
        guard
            let simulatedOutcome = simulationScenario.simulatedOutcome(
                at: currentDate,
                fetchIndex: fetchIndex,
                firstFetchDate: firstFetchDate
            )
        else {
            throw GlucoseProviderError.unexpectedResponse(description: "Live data is not simulated.")
        }
        return try simulatedOutcome.get()
    }

    func fetchRecentReadings(withinMinutes lookbackMinutes: Int) async throws -> [GlucoseReading] {
        [try await fetchLatestReading()]
    }
}

nonisolated struct SimulatedFetchHistory: Sendable {
    var answeredFetchCount = 0
    var firstFetchDate: Date?
}
#endif
