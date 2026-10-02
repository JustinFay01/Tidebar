//
//  GlucoseMonitoringTests.swift
//  TidebarTests
//

import AppKit
import Foundation
import os
import Testing
@testable import Tidebar

/// Provider returning queued results in order and counting calls.
final class StubGlucoseProvider: GlucoseProvider {
    let providerDisplayName = "Stub Provider"
    private let lockedQueuedResults = OSAllocatedUnfairLock(uncheckedState: [Result<GlucoseReading, Error>]())
    private let lockedFetchCount = OSAllocatedUnfairLock(initialState: 0)

    var fetchCount: Int {
        lockedFetchCount.withLock { $0 }
    }

    func enqueue(_ queuedResult: Result<GlucoseReading, Error>) {
        lockedQueuedResults.withLock { $0.append(queuedResult) }
    }

    func fetchLatestReading() async throws -> GlucoseReading {
        lockedFetchCount.withLock { $0 += 1 }
        let nextResult = lockedQueuedResults.withLock { queuedResults in
            queuedResults.isEmpty ? nil : queuedResults.removeFirst()
        }
        guard let nextResult else {
            throw GlucoseProviderError.unexpectedResponse(description: "No stubbed result")
        }
        return try nextResult.get()
    }

    func fetchRecentReadings(withinMinutes lookbackMinutes: Int) async throws -> [GlucoseReading] {
        [try await fetchLatestReading()]
    }
}

private let referenceDate = Date(timeIntervalSince1970: 1_690_000_000)

private func makeReading(
    secondsBeforeReference: TimeInterval,
    valueMgPerDeciliter: Int = 112,
    trendDirection: TrendDirection = .flat
) -> GlucoseReading {
    GlucoseReading(
        valueMgPerDeciliter: valueMgPerDeciliter,
        trendDirection: trendDirection,
        readingTimestamp: referenceDate.addingTimeInterval(-secondsBeforeReference)
    )
}

// MARK: - Freshness classification

struct GlucoseReadingFreshnessTests {
    enum ExpectedDisplayKind: Sendable {
        case current, aging, unknown
    }

    @Test(arguments: [
        (0.0, .current),
        (-120.0, .current),
        (359.0, .current),
        (360.0, .aging),
        (480.0, .aging),
        (720.0, .aging),
        (721.0, .unknown),
        (10_800.0, .unknown),
    ] as [(TimeInterval, ExpectedDisplayKind)])
    func classifiesByReadingAge(readingAgeSeconds: TimeInterval, expectedDisplayKind: ExpectedDisplayKind) {
        let latestReading = makeReading(secondsBeforeReference: readingAgeSeconds)

        let displayState = GlucoseReadingFreshness.classifyDisplayState(
            latestReading: latestReading,
            unavailableReason: nil,
            currentDate: referenceDate
        )

        switch (displayState, expectedDisplayKind) {
        case (.current(let shownReading), .current), (.aging(let shownReading), .aging):
            #expect(shownReading == latestReading)
        case (.unknown(let reason), .unknown):
            #expect(reason.contains("min ago"))
        default:
            Issue.record("Expected \(expectedDisplayKind) but got \(displayState)")
        }
    }

    @Test func unknownWithoutAnyReading() {
        let displayState = GlucoseReadingFreshness.classifyDisplayState(
            latestReading: nil,
            unavailableReason: nil,
            currentDate: referenceDate
        )
        #expect(displayState == .unknown(reason: GlucoseReadingFreshness.awaitingFirstReadingReason))
    }

    @Test func unavailableReasonWinsOverFreshReading() {
        let displayState = GlucoseReadingFreshness.classifyDisplayState(
            latestReading: makeReading(secondsBeforeReference: 30),
            unavailableReason: "Network unavailable.",
            currentDate: referenceDate
        )
        #expect(displayState == .unknown(reason: "Network unavailable."))
    }
}

// MARK: - Scheduling

struct GlucoseFetchSchedulerTests {
    @Test(arguments: [
        (0.0, 315.0),
        (60.0, 255.0),
        (300.0, 15.0),
        (314.0, 1.0),
        (315.0, 60.0),
        (900.0, 60.0),
        (-600.0, 315.0),
    ])
    func schedulesNextFetchAfterExpectedReading(readingAgeSeconds: TimeInterval, expectedDelaySeconds: TimeInterval) {
        let delaySeconds = GlucoseFetchScheduler.delayAfterSuccessfulFetch(
            latestReadingTimestamp: referenceDate.addingTimeInterval(-readingAgeSeconds),
            currentDate: referenceDate
        )
        #expect(abs(delaySeconds - expectedDelaySeconds) < 0.001)
    }

    @Test(arguments: [(1, 15.0), (2, 30.0), (3, 60.0), (4, 120.0), (5, 240.0), (6, 300.0), (20, 300.0)])
    func backsOffExponentiallyAfterFailures(consecutiveFailureCount: Int, expectedDelaySeconds: TimeInterval) {
        let delaySeconds = GlucoseFetchScheduler.delayAfterFailedFetch(
            fetchFailure: .networkUnavailable,
            consecutiveFailureCount: consecutiveFailureCount
        )
        #expect(delaySeconds == expectedDelaySeconds)
    }

    @Test(arguments: [GlucoseProviderError.invalidCredentials, .accountLockedOrRateLimited])
    func accountProblemsWaitTheFullCap(fetchFailure: GlucoseProviderError) {
        let delaySeconds = GlucoseFetchScheduler.delayAfterFailedFetch(fetchFailure: fetchFailure, consecutiveFailureCount: 1)
        #expect(delaySeconds == GlucoseFetchScheduler.maximumFailureRetryInterval)
    }
}

// MARK: - Formatting

struct GlucoseStatusFormatterTests {
    static let englishLocale = Locale(identifier: "en_US")

    @Test(arguments: [
        (TrendDirection.doubleUp, ["arrow.up", "arrow.up"]),
        (.singleUp, ["arrow.up"]),
        (.fortyFiveUp, ["arrow.up.right"]),
        (.flat, ["arrow.right"]),
        (.fortyFiveDown, ["arrow.down.right"]),
        (.singleDown, ["arrow.down"]),
        (.doubleDown, ["arrow.down", "arrow.down"]),
        (.notComputable, ["questionmark"]),
        (.rateOutOfRange, ["questionmark"]),
        (.none, ["questionmark"]),
    ] as [(TrendDirection, [String])])
    func formatsCurrentReadingWithTrendSymbols(trendDirection: TrendDirection, expectedSymbolNames: [String]) {
        let statusContent = GlucoseStatusFormatter.menuBarStatusContent(
            for: .current(makeReading(secondsBeforeReference: 60, trendDirection: trendDirection)),
            glucoseUnit: .milligramsPerDeciliter,
            currentDate: referenceDate,
            locale: Self.englishLocale
        )
        #expect(statusContent == GlucoseStatusFormatter.MenuBarStatusContent(
            valueText: "112",
            trendSymbolNames: expectedSymbolNames,
            ageSuffixText: nil,
            isDimmed: false
        ))
    }

    @Test func reservesWidthForEverySingleArrowButNotDoubles() {
        let widthReservingContents = GlucoseStatusFormatter.widthReservingContents(for: .milligramsPerDeciliter)

        #expect(widthReservingContents.map(\.trendSymbolNames) == [
            ["arrow.up"], ["arrow.up.right"], ["arrow.right"], ["arrow.down.right"], ["arrow.down"], ["questionmark"],
        ])
        #expect(widthReservingContents.allSatisfy { $0.valueText == "000" && $0.ageSuffixText == nil })
    }

    @Test(arguments: TrendDirection.allCases)
    func everyTrendSymbolExistsOnThisSystem(trendDirection: TrendDirection) {
        for trendSymbolName in GlucoseStatusFormatter.trendSymbolNames(for: trendDirection) {
            #expect(NSImage(systemSymbolName: trendSymbolName, accessibilityDescription: nil) != nil)
        }
    }

    @Test(arguments: [
        (GlucoseUnit.milligramsPerDeciliter, "en_US", "112"),
        (GlucoseUnit.millimolesPerLiter, "en_US", "6.2"),
        (GlucoseUnit.millimolesPerLiter, "de_DE", "6,2"),
    ])
    func formatsAgingReadingDimmedWithAgeSuffix(glucoseUnit: GlucoseUnit, localeIdentifier: String, expectedValueText: String) {
        let statusContent = GlucoseStatusFormatter.menuBarStatusContent(
            for: .aging(makeReading(secondsBeforeReference: 510)),
            glucoseUnit: glucoseUnit,
            currentDate: referenceDate,
            locale: Locale(identifier: localeIdentifier)
        )
        #expect(statusContent == GlucoseStatusFormatter.MenuBarStatusContent(
            valueText: expectedValueText,
            trendSymbolNames: ["arrow.right"],
            ageSuffixText: "8m",
            isDimmed: true
        ))
    }

    @Test(arguments: GlucoseUnit.allCases)
    func formatsUnknownState(glucoseUnit: GlucoseUnit) {
        let statusContent = GlucoseStatusFormatter.menuBarStatusContent(
            for: .unknown(reason: "anything"),
            glucoseUnit: glucoseUnit,
            currentDate: referenceDate
        )
        #expect(statusContent.valueText == "---")
        #expect(statusContent.trendSymbolNames == ["questionmark"])
        #expect(statusContent.ageSuffixText == nil)
        #expect(!statusContent.isDimmed)
    }

    @Test(arguments: [
        (20.0, "Just now"),
        (190.0, "3 min ago"),
        (3_540.0, "59 min ago"),
        (3_600.0, "1 hr ago"),
        (3_900.0, "1 hr 5 min ago"),
    ])
    func describesRelativeAge(readingAgeSeconds: TimeInterval, expectedDescription: String) {
        let ageDescription = GlucoseStatusFormatter.relativeAgeDescription(
            of: makeReading(secondsBeforeReference: readingAgeSeconds),
            currentDate: referenceDate
        )
        #expect(ageDescription == expectedDescription)
    }
}

// MARK: - Monitor

@MainActor
struct GlucoseMonitorTests {
    let testClock = MutableTestClock(startingAt: referenceDate)
    let stubProvider = StubGlucoseProvider()

    func makeMonitor(providerSetupResult: Result<any GlucoseProvider, GlucoseProviderSetupError>? = nil) -> GlucoseMonitor {
        let resolvedSetupResult = providerSetupResult ?? .success(stubProvider)
        let monitor = GlucoseMonitor(
            providerBuilder: { resolvedSetupResult },
            currentDateProvider: testClock.makeDateProvider(),
            sleepFunction: { _ in throw CancellationError() }
        )
        monitor.rebuildProviderAndRefresh()
        return monitor
    }

    @Test func missingConfigurationShowsUnknownAndDoesNotPoll() async {
        let monitor = makeMonitor(providerSetupResult: .failure(.missingConfiguration))

        let nextDelay = await monitor.performFetch()

        #expect(nextDelay == nil)
        #expect(monitor.displayState == .unknown(reason: GlucoseProviderSetupError.missingConfiguration.userFacingDescription))
        #expect(monitor.providerDisplayName == nil)
    }

    @Test func successfulFetchShowsCurrentReadingAndSchedulesNextReading() async {
        let freshReading = makeReading(secondsBeforeReference: 60)
        stubProvider.enqueue(.success(freshReading))
        let monitor = makeMonitor()

        let nextDelay = await monitor.performFetch()

        #expect(monitor.displayState == .current(freshReading))
        #expect(monitor.providerDisplayName == "Stub Provider")
        #expect(nextDelay == 255)
    }

    @Test func readingAgesThenBecomesUnknownAsClockAdvances() async {
        let freshReading = makeReading(secondsBeforeReference: 60)
        stubProvider.enqueue(.success(freshReading))
        let monitor = makeMonitor()
        _ = await monitor.performFetch()

        testClock.advance(bySeconds: 6 * 60)
        monitor.updateDisplayEvaluationDate()
        #expect(monitor.displayState == .aging(freshReading))

        testClock.advance(bySeconds: 6 * 60)
        monitor.updateDisplayEvaluationDate()
        guard case .unknown = monitor.displayState else {
            Issue.record("Expected unknown after 13 minutes, got \(monitor.displayState)")
            return
        }
    }

    @Test func sameReadingAgainRetriesEveryMinute() async {
        let freshReading = makeReading(secondsBeforeReference: 60)
        stubProvider.enqueue(.success(freshReading))
        stubProvider.enqueue(.success(freshReading))
        let monitor = makeMonitor()
        _ = await monitor.performFetch()

        testClock.advance(bySeconds: 255)
        let nextDelay = await monitor.performFetch()

        #expect(nextDelay == GlucoseFetchScheduler.awaitingNewReadingRetryInterval)
    }

    @Test func failuresShowUnknownAndBackOff() async {
        stubProvider.enqueue(.success(makeReading(secondsBeforeReference: 30)))
        stubProvider.enqueue(.failure(GlucoseProviderError.networkUnavailable))
        stubProvider.enqueue(.failure(GlucoseProviderError.networkUnavailable))
        let monitor = makeMonitor()
        _ = await monitor.performFetch()

        let firstFailureDelay = await monitor.performFetch()
        let secondFailureDelay = await monitor.performFetch()

        #expect(monitor.displayState == .unknown(reason: GlucoseProviderError.networkUnavailable.userFacingDescription))
        #expect(monitor.latestReading != nil)
        #expect(firstFailureDelay == 15)
        #expect(secondFailureDelay == 30)
    }

    @Test func recoveryAfterFailureResetsBackoff() async {
        let recoveredReading = makeReading(secondsBeforeReference: 0)
        stubProvider.enqueue(.failure(GlucoseProviderError.noRecentReadings))
        stubProvider.enqueue(.success(recoveredReading))
        let monitor = makeMonitor()

        _ = await monitor.performFetch()
        #expect(monitor.lastFetchError == .noRecentReadings)
        _ = await monitor.performFetch()

        #expect(monitor.lastFetchError == nil)
        #expect(monitor.displayState == .current(recoveredReading))
    }

    @Test func nonProviderErrorsAreNormalized() async {
        stubProvider.enqueue(.failure(URLError(.badURL)))
        let monitor = makeMonitor()

        _ = await monitor.performFetch()

        guard case .unexpectedResponse = monitor.lastFetchError else {
            Issue.record("Expected unexpectedResponse, got \(String(describing: monitor.lastFetchError))")
            return
        }
    }

    @Test func cancellationLeavesStateUntouched() async {
        stubProvider.enqueue(.failure(CancellationError()))
        let monitor = makeMonitor()

        let nextDelay = await monitor.performFetch()

        #expect(nextDelay == nil)
        #expect(monitor.lastFetchError == nil)
    }

    @Test func applyingNewSettingsClearsPreviousReading() async {
        stubProvider.enqueue(.success(makeReading(secondsBeforeReference: 30)))
        let monitor = makeMonitor()
        _ = await monitor.performFetch()

        monitor.rebuildProviderAndRefresh()

        #expect(monitor.latestReading == nil)
        #expect(monitor.displayState == .unknown(reason: GlucoseReadingFreshness.awaitingFirstReadingReason))
    }
}
