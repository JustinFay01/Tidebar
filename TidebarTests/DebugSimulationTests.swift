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
        let groupedScenarios =
            DebugSimulationScenario.errorScenarios + DebugSimulationScenario.setupScenarios
            + DebugSimulationScenario.readingScenarios
        #expect(Set(groupedScenarios) == Set(DebugSimulationScenario.allCases).subtracting([.liveData]))
        #expect(groupedScenarios.count == Set(groupedScenarios).count)
    }

    @Test func liveDataHasNoSimulatedOutcome() {
        #expect(
            DebugSimulationScenario.liveData.simulatedOutcome(
                at: testClock.currentDate,
                fetchIndex: 0,
                firstFetchDate: testClock.currentDate
            ) == nil)
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
            (.singleUpTrend, .current, .singleUp),
            (.singleDownTrend, .current, .singleDown),
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

        #expect(monitor.currentReading?.trendDirection == expectedTrendDirection)
        switch (monitor.displayState, expectedDisplayKind) {
        case (.current, .current), (.aging, .aging), (.unknown, .unknown):
            break
        default:
            Issue.record("Expected \(expectedDisplayKind) but got \(monitor.displayState)")
        }
    }

    @Test(
        arguments: [
            (DebugSimulationScenario.currentReading, 0),
            (.singleUpTrend, 8),
            (.singleDownTrend, -8),
            (.doubleUpTrend, 18),
            (.doubleDownTrend, -18),
            (.indeterminateTrend, 0),
        ] as [(DebugSimulationScenario, Int)])
    func readingScenariosShowTheirChangeFromTheSecondFetchOn(
        simulationScenario: DebugSimulationScenario,
        expectedDifferenceMgPerDeciliter: Int
    ) async {
        let monitor = makeMonitor(simulating: simulationScenario)

        let delayAfterEarlierReading = await monitor.performFetch()
        #expect(delayAfterEarlierReading == GlucoseFetchScheduler.readingPublicationGracePeriod)
        #expect(differenceShown(by: monitor) == nil)

        testClock.advance(bySeconds: 15)
        _ = await monitor.performFetch()
        #expect(monitor.currentReading?.valueMgPerDeciliter == DebugSimulationScenario.simulatedValueMgPerDeciliter)
        #expect(differenceShown(by: monitor) == expectedDifferenceMgPerDeciliter)

        testClock.advance(bySeconds: GlucoseFetchScheduler.sensorReadingInterval)
        _ = await monitor.performFetch()
        #expect(differenceShown(by: monitor) == expectedDifferenceMgPerDeciliter)
    }

    @Test(arguments: [DebugSimulationScenario.agingReading, .staleReading])
    func agedReadingScenariosKeepOneReadingAcrossRefreshes(simulationScenario: DebugSimulationScenario) async {
        let monitor = makeMonitor(simulating: simulationScenario)

        _ = await monitor.performFetch()
        let firstReading = monitor.currentReading
        testClock.advance(bySeconds: GlucoseFetchScheduler.awaitingNewReadingRetryInterval)
        _ = await monitor.performFetch()

        #expect(monitor.currentReading == firstReading)
        #expect(monitor.previousReading == nil)
    }

    @Test(arguments: [DebugSimulationScenario.doubleUpTrend, .doubleDownTrend])
    func driftingReadingsStayWithinDexcomRange(simulationScenario: DebugSimulationScenario) throws {
        let simulatedOutcome = simulationScenario.simulatedOutcome(
            at: testClock.currentDate,
            fetchIndex: 1_000,
            firstFetchDate: testClock.currentDate
        )
        let simulatedReading = try #require(simulatedOutcome).get()

        #expect(DebugSimulationScenario.simulatedValueRangeMgPerDeciliter.contains(simulatedReading.valueMgPerDeciliter))
    }

    private func differenceShown(by monitor: GlucoseMonitor) -> Int? {
        switch monitor.displayState {
        case .current(let readings), .aging(let readings):
            DisplayedReadings.differenceMgPerDeciliter(from: readings.previousReading, to: readings.currentReading)
        case .unknown:
            nil
        }
    }

    @Test func selectingScenarioSwapsProviderAndBackToLive() {
        let debugSimulationController = DebugSimulationController()
        let monitor = GlucoseMonitor(
            providerBuilder: {
                debugSimulationController.makeSimulatedProviderSetupResultIfActive() ?? .failure(.missingConfiguration)
            },
            sleepFunction: { _ in throw CancellationError() }
        )

        debugSimulationController.selectScenario(.networkUnavailable, glucoseMonitor: monitor)
        #expect(monitor.providerDisplayName == "Simulated: Network Unavailable")

        debugSimulationController.selectScenario(.liveData, glucoseMonitor: monitor)
        #expect(monitor.providerDisplayName == nil)
        #expect(monitor.providerSetupError == .missingConfiguration)
    }

    @Test func keychainUnreadableUntilRetryRecoversToLiveDataOnTheNextBuild() async {
        let debugSimulationController = DebugSimulationController()
        let liveProvider = SimulatedGlucoseProvider(
            simulationScenario: .currentReading,
            simulatedLatency: .zero,
            currentDateProvider: testClock.makeDateProvider()
        )
        let monitor = GlucoseMonitor(
            providerBuilder: { debugSimulationController.makeSimulatedProviderSetupResultIfActive() ?? .success(liveProvider) },
            currentDateProvider: testClock.makeDateProvider(),
            sleepFunction: { _ in throw CancellationError() }
        )

        debugSimulationController.selectScenario(.keychainUnreadableUntilRetry, glucoseMonitor: monitor)
        #expect(monitor.providerSetupError == DebugSimulationScenario.keychainUnreadableUntilRetry.simulatedSetupError)
        #expect(await monitor.performFetch() == GlucoseFetchScheduler.providerSetupRetryInterval)

        _ = await monitor.performFetch()

        #expect(debugSimulationController.activeScenario == .liveData)
        #expect(monitor.providerSetupError == nil)
        #expect(monitor.currentReading != nil)
    }
}
#endif
