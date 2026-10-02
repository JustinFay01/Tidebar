//
//  DebugSimulationTests.swift
//  TidebarTests
//

#if DEBUG
import Foundation
import Testing
@testable import Tidebar

@MainActor
struct DebugSimulationTests {
    enum ExpectedDisplayKind: Sendable {
        case current, aging, unknown
    }

    let testClock = MutableTestClock()

    func makeMonitor(simulating simulationScenario: DebugSimulationScenario) -> GlucoseMonitor {
        let simulatedProvider = SimulatedGlucoseProvider(
            simulationScenario: simulationScenario,
            simulatedLatency: .zero,
            currentDateProvider: testClock.makeDateProvider()
        )
        let monitor = GlucoseMonitor(
            providerBuilder: { .success(simulatedProvider) },
            currentDateProvider: testClock.makeDateProvider(),
            sleepFunction: { _ in throw CancellationError() }
        )
        monitor.resetProviderAndReadings()
        return monitor
    }

    @Test func scenarioGroupsCoverEverythingExceptLiveData() {
        let groupedScenarios = DebugSimulationScenario.errorScenarios + DebugSimulationScenario.readingScenarios
        #expect(Set(groupedScenarios) == Set(DebugSimulationScenario.allCases).subtracting([.liveData]))
        #expect(groupedScenarios.count == Set(groupedScenarios).count)
    }

    @Test func liveDataHasNoSimulatedOutcome() {
        #expect(DebugSimulationScenario.liveData.simulatedOutcome(at: testClock.currentDate) == nil)
    }

    @Test(arguments: [
        (DebugSimulationScenario.invalidCredentials, GlucoseProviderError.invalidCredentials),
        (.networkUnavailable, .networkUnavailable),
        (.noRecentReadings, .noRecentReadings),
        (.accountLockedOrRateLimited, .accountLockedOrRateLimited),
        (.unexpectedResponse, .unexpectedResponse(description: "Simulated server error.")),
    ])
    func errorScenariosSurfaceProviderErrors(simulationScenario: DebugSimulationScenario, expectedError: GlucoseProviderError) async {
        let monitor = makeMonitor(simulating: simulationScenario)

        _ = await monitor.performFetch()

        #expect(monitor.lastFetchError == expectedError)
        #expect(monitor.displayState == .unknown(reason: expectedError.statusMessage))
    }

    @Test(
        arguments: [
            (DebugSimulationScenario.currentReading, ExpectedDisplayKind.current, TrendDirection.flat),
            (.agingReading, .aging, .flat),
            (.staleReading, .unknown, .flat),
            (.doubleUpTrend, .current, .doubleUp),
            (.doubleDownTrend, .current, .doubleDown),
            (.indeterminateTrend, .current, .notComputable),
        ] as [(DebugSimulationScenario, ExpectedDisplayKind, TrendDirection)])
    func readingScenariosProduceExpectedDisplayState(
        simulationScenario: DebugSimulationScenario,
        expectedDisplayKind: ExpectedDisplayKind,
        expectedTrendDirection: TrendDirection
    ) async {
        let monitor = makeMonitor(simulating: simulationScenario)

        _ = await monitor.performFetch()

        #expect(monitor.latestReading?.trendDirection == expectedTrendDirection)
        switch (monitor.displayState, expectedDisplayKind) {
        case (.current, .current), (.aging, .aging), (.unknown, .unknown):
            break
        default:
            Issue.record("Expected \(expectedDisplayKind) but got \(monitor.displayState)")
        }
    }

    @Test func selectingScenarioSwapsProviderAndBackToLive() {
        let debugSimulationController = DebugSimulationController()
        let monitor = GlucoseMonitor(
            providerBuilder: {
                if let simulatedProvider = debugSimulationController.makeSimulatedProviderIfActive() {
                    return .success(simulatedProvider)
                }
                return .failure(.missingConfiguration)
            },
            sleepFunction: { _ in throw CancellationError() }
        )

        debugSimulationController.selectScenario(.networkUnavailable, glucoseMonitor: monitor)
        #expect(monitor.providerDisplayName == "Simulated: Network Unavailable")

        debugSimulationController.selectScenario(.liveData, glucoseMonitor: monitor)
        #expect(monitor.providerDisplayName == nil)
        #expect(monitor.providerSetupError == .missingConfiguration)
    }
}
#endif
