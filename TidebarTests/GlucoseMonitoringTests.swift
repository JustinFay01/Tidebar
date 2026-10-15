//
//  GlucoseMonitoringTests.swift
//  TidebarTests
//

import AppKit
import Foundation
import Testing
import os

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

    @Test(
        arguments: [
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
            previousReading: nil,
            unavailableReason: nil,
            currentDate: referenceDate
        )

        switch (displayState, expectedDisplayKind) {
        case (.current(let shownReadings), .current), (.aging(let shownReadings), .aging):
            #expect(shownReadings.currentReading == latestReading)
        case (.unknown(let reason), .unknown):
            #expect(reason.contains("min ago"))
        default:
            Issue.record("Expected \(expectedDisplayKind) but got \(displayState)")
        }
    }

    @Test func unknownWithoutAnyReading() {
        let displayState = GlucoseReadingFreshness.classifyDisplayState(
            latestReading: nil,
            previousReading: nil,
            unavailableReason: nil,
            currentDate: referenceDate
        )
        #expect(displayState == .unknown(reason: GlucoseReadingFreshness.awaitingFirstReadingReason))
    }

    @Test func keepsThePreviousReadingAlongsideTheCurrentOne() {
        let currentReading = makeReading(secondsBeforeReference: 60)
        let previousReading = makeReading(secondsBeforeReference: 360, valueMgPerDeciliter: 104)

        let displayState = GlucoseReadingFreshness.classifyDisplayState(
            latestReading: currentReading,
            previousReading: previousReading,
            unavailableReason: nil,
            currentDate: referenceDate
        )

        #expect(displayState == .current(DisplayedReadings(currentReading: currentReading, previousReading: previousReading)))
    }

    @Test func unavailableReasonWinsOverFreshReading() {
        let displayState = GlucoseReadingFreshness.classifyDisplayState(
            latestReading: makeReading(secondsBeforeReference: 30),
            previousReading: nil,
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

struct DisplayedReadingsTests {
    @Test(
        arguments: [
            (300.0, 104, 8),
            (300.0, 120, -8),
            (300.0, 112, 0),
            (450.0, 104, 8),
            (451.0, 104, nil),
            (600.0, 104, nil),
            (0.0, 104, nil),
        ] as [(TimeInterval, Int, Int?)])
    func differenceOnlyBetweenConsecutiveReadings(
        previousReadingSecondsBeforeCurrent: TimeInterval,
        previousValueMgPerDeciliter: Int,
        expectedDifferenceMgPerDeciliter: Int?
    ) {
        let currentReading = makeReading(secondsBeforeReference: 0)
        let previousReading = makeReading(
            secondsBeforeReference: previousReadingSecondsBeforeCurrent,
            valueMgPerDeciliter: previousValueMgPerDeciliter
        )

        let differenceMgPerDeciliter = DisplayedReadings.differenceMgPerDeciliter(from: previousReading, to: currentReading)

        #expect(differenceMgPerDeciliter == expectedDifferenceMgPerDeciliter)
    }

    @Test func noDifferenceWithoutAPreviousReading() {
        #expect(DisplayedReadings.differenceMgPerDeciliter(from: nil, to: makeReading(secondsBeforeReference: 0)) == nil)
    }
}

struct GlucoseStatusFormatterTests {
    static let englishLocale = Locale(identifier: "en_US")

    @Test(
        arguments: [
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
            for: .current(
                DisplayedReadings(
                    currentReading: makeReading(secondsBeforeReference: 60, trendDirection: trendDirection),
                    previousReading: nil
                )),
            glucoseUnit: .milligramsPerDeciliter,
            currentDate: referenceDate,
            showsDifference: true,
            locale: Self.englishLocale
        )
        #expect(
            statusContent
                == GlucoseStatusFormatter.MenuBarStatusContent(
                    valueText: "112",
                    trendSymbolNames: expectedSymbolNames,
                    differenceContent: nil,
                    ageSuffixText: nil,
                    isDimmed: false
                ))
    }

    @Test func reservesWidthForEverySingleArrowButNotDoubles() {
        let widthReservingContents = GlucoseStatusFormatter.widthReservingContents(for: .milligramsPerDeciliter, isDifferenceShown: false)

        #expect(
            widthReservingContents.map(\.trendSymbolNames) == [
                ["arrow.up"], ["arrow.up.right"], ["arrow.right"], ["arrow.down.right"], ["arrow.down"], ["questionmark"],
            ])
        #expect(
            widthReservingContents.allSatisfy {
                $0.valueText == "000" && $0.differenceContent == nil && $0.ageSuffixText == nil
            })
    }

    @Test func reservesWidthForTheDifferenceOnlyWhileOneIsShown() {
        let widthReservingContents = GlucoseStatusFormatter.widthReservingContents(for: .milligramsPerDeciliter, isDifferenceShown: true)

        #expect(
            widthReservingContents.allSatisfy {
                $0.differenceContent == GlucoseStatusFormatter.DifferenceContent(signSymbolName: "plus", magnitudeText: "00")
            })
    }

    @Test(arguments: [
        (GlucoseUnit.milligramsPerDeciliter, "en_US", 104, "plus", "8"),
        (GlucoseUnit.milligramsPerDeciliter, "en_US", 120, "minus", "8"),
        (GlucoseUnit.milligramsPerDeciliter, "en_US", 112, "plusminus", "0"),
        (GlucoseUnit.millimolesPerLiter, "en_US", 120, "minus", "0.4"),
        (GlucoseUnit.millimolesPerLiter, "de_DE", 120, "minus", "0,4"),
    ])
    func formatsDifferenceAsSignSymbolAndUnsignedAmount(
        glucoseUnit: GlucoseUnit,
        localeIdentifier: String,
        previousValueMgPerDeciliter: Int,
        expectedSignSymbolName: String,
        expectedMagnitudeText: String
    ) {
        let readings = DisplayedReadings(
            currentReading: makeReading(secondsBeforeReference: 60),
            previousReading: makeReading(secondsBeforeReference: 360, valueMgPerDeciliter: previousValueMgPerDeciliter)
        )

        let statusContent = GlucoseStatusFormatter.menuBarStatusContent(
            for: .current(readings),
            glucoseUnit: glucoseUnit,
            currentDate: referenceDate,
            showsDifference: true,
            locale: Locale(identifier: localeIdentifier)
        )

        #expect(
            statusContent.differenceContent
                == GlucoseStatusFormatter.DifferenceContent(
                    signSymbolName: expectedSignSymbolName,
                    magnitudeText: expectedMagnitudeText
                ))
    }

    @Test(arguments: [-1, 0, 1])
    func everyDifferenceSignSymbolExistsOnThisSystem(differenceMgPerDeciliter: Int) {
        let signSymbolName = GlucoseStatusFormatter.differenceSignSymbolName(for: differenceMgPerDeciliter)
        #expect(NSImage(systemSymbolName: signSymbolName, accessibilityDescription: nil) != nil)
    }

    @Test(arguments: [
        (104, "Glucose 112 mg/dL, Steady, up 8 since the last reading"),
        (120, "Glucose 112 mg/dL, Steady, down 8 since the last reading"),
        (112, "Glucose 112 mg/dL, Steady, no change since the last reading"),
    ])
    func speaksDifferenceInWords(previousValueMgPerDeciliter: Int, expectedDescription: String) {
        let readings = DisplayedReadings(
            currentReading: makeReading(secondsBeforeReference: 60),
            previousReading: makeReading(secondsBeforeReference: 360, valueMgPerDeciliter: previousValueMgPerDeciliter)
        )

        let accessibilityDescription = GlucoseStatusFormatter.accessibilityDescription(
            for: .current(readings),
            glucoseUnit: .milligramsPerDeciliter,
            showsDifference: true,
            locale: Self.englishLocale
        )

        #expect(accessibilityDescription == expectedDescription)
    }

    @Test func leavesOutTheDifferenceWhenTurnedOffForTheMenuBar() {
        let readings = DisplayedReadings(
            currentReading: makeReading(secondsBeforeReference: 60),
            previousReading: makeReading(secondsBeforeReference: 360, valueMgPerDeciliter: 104)
        )

        let statusContent = GlucoseStatusFormatter.menuBarStatusContent(
            for: .current(readings),
            glucoseUnit: .milligramsPerDeciliter,
            currentDate: referenceDate,
            showsDifference: false,
            locale: Self.englishLocale
        )
        let accessibilityDescription = GlucoseStatusFormatter.accessibilityDescription(
            for: .current(readings),
            glucoseUnit: .milligramsPerDeciliter,
            showsDifference: false,
            locale: Self.englishLocale
        )

        #expect(statusContent.differenceContent == nil)
        #expect(accessibilityDescription == "Glucose 112 mg/dL, Steady")
    }

    @Test(arguments: [
        (GlucoseUnit.milligramsPerDeciliter, "en_US", 104, "+8"),
        (GlucoseUnit.milligramsPerDeciliter, "en_US", 120, "\u{2212}8"),
        (GlucoseUnit.milligramsPerDeciliter, "en_US", 112, "\u{00B1}0"),
        (GlucoseUnit.millimolesPerLiter, "de_DE", 120, "\u{2212}0,4"),
    ])
    func formatsPlainTextDifferenceForTheDropdown(
        glucoseUnit: GlucoseUnit,
        localeIdentifier: String,
        previousValueMgPerDeciliter: Int,
        expectedText: String
    ) {
        let readings = DisplayedReadings(
            currentReading: makeReading(secondsBeforeReference: 60),
            previousReading: makeReading(secondsBeforeReference: 360, valueMgPerDeciliter: previousValueMgPerDeciliter)
        )

        let differenceText = GlucoseStatusFormatter.differencePlainText(
            for: readings,
            glucoseUnit: glucoseUnit,
            locale: Locale(identifier: localeIdentifier)
        )

        #expect(differenceText == expectedText)
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
            for: .aging(DisplayedReadings(currentReading: makeReading(secondsBeforeReference: 510), previousReading: nil)),
            glucoseUnit: glucoseUnit,
            currentDate: referenceDate,
            showsDifference: true,
            locale: Locale(identifier: localeIdentifier)
        )
        #expect(
            statusContent
                == GlucoseStatusFormatter.MenuBarStatusContent(
                    valueText: expectedValueText,
                    trendSymbolNames: ["arrow.right"],
                    differenceContent: nil,
                    ageSuffixText: "8m",
                    isDimmed: true
                ))
    }

    @Test(arguments: GlucoseUnit.allCases)
    func formatsUnknownState(glucoseUnit: GlucoseUnit) {
        let statusContent = GlucoseStatusFormatter.menuBarStatusContent(
            for: .unknown(reason: "anything"),
            glucoseUnit: glucoseUnit,
            currentDate: referenceDate,
            showsDifference: true
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
    let stubConnectivityMonitor = StubNetworkConnectivityMonitor()

    func makeMonitor(providerSetupResult: Result<any GlucoseProvider, GlucoseProviderSetupError>? = nil) -> GlucoseMonitor {
        let resolvedSetupResult = providerSetupResult ?? .success(stubProvider)
        let monitor = GlucoseMonitor(
            providerBuilder: { resolvedSetupResult },
            currentDateProvider: testClock.makeDateProvider(),
            sleepFunction: { _ in throw CancellationError() },
            networkConnectivityMonitor: stubConnectivityMonitor
        )
        monitor.resetProviderAndReadings()
        return monitor
    }

    @Test func missingConfigurationShowsUnknownAndDoesNotPoll() async {
        let monitor = makeMonitor(providerSetupResult: .failure(.missingConfiguration))

        let nextDelay = await monitor.performFetch()

        #expect(nextDelay == nil)
        #expect(monitor.displayState == .unknown(reason: GlucoseProviderSetupError.missingConfiguration.statusMessage))
        #expect(monitor.providerDisplayName == nil)
    }

    @Test func unreadablePasswordRetriesProviderSetupAndRecovers() async {
        let freshReading = makeReading(secondsBeforeReference: 60)
        stubProvider.enqueue(.success(freshReading))
        let unreadablePassword = GlucoseProviderSetupError.passwordUnreadable(
            keychainFailure: KeychainOperationError(operationStatus: errSecInteractionNotAllowed)
        )
        var providerSetupResult: Result<any GlucoseProvider, GlucoseProviderSetupError> = .failure(unreadablePassword)
        let monitor = GlucoseMonitor(
            providerBuilder: { providerSetupResult },
            currentDateProvider: testClock.makeDateProvider(),
            sleepFunction: { _ in throw CancellationError() },
            networkConnectivityMonitor: stubConnectivityMonitor
        )
        monitor.resetProviderAndReadings()

        let retryDelay = await monitor.performFetch()
        #expect(retryDelay == GlucoseFetchScheduler.providerSetupRetryInterval)
        #expect(monitor.providerSetupError == unreadablePassword)

        providerSetupResult = .success(stubProvider)
        let nextDelay = await monitor.performFetch()

        #expect(monitor.providerSetupError == nil)
        #expect(monitor.displayState == .current(DisplayedReadings(currentReading: freshReading, previousReading: nil)))
        #expect(nextDelay == 255)
    }

    @Test func successfulFetchShowsCurrentReadingAndSchedulesNextReading() async {
        let freshReading = makeReading(secondsBeforeReference: 60)
        stubProvider.enqueue(.success(freshReading))
        let monitor = makeMonitor()

        let nextDelay = await monitor.performFetch()

        #expect(monitor.displayState == .current(DisplayedReadings(currentReading: freshReading, previousReading: nil)))
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
        #expect(monitor.displayState == .aging(DisplayedReadings(currentReading: freshReading, previousReading: nil)))

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

    @Test func newReadingKeepsTheReadingBeforeIt() async {
        let earlierReading = makeReading(secondsBeforeReference: 360, valueMgPerDeciliter: 104)
        let newerReading = makeReading(secondsBeforeReference: 60)
        stubProvider.enqueue(.success(earlierReading))
        stubProvider.enqueue(.success(newerReading))
        let monitor = makeMonitor()

        _ = await monitor.performFetch()
        _ = await monitor.performFetch()

        #expect(monitor.displayState == .current(DisplayedReadings(currentReading: newerReading, previousReading: earlierReading)))
    }

    @Test func sameReadingAgainKeepsTheReadingBeforeIt() async {
        let earlierReading = makeReading(secondsBeforeReference: 360, valueMgPerDeciliter: 104)
        let newerReading = makeReading(secondsBeforeReference: 60)
        stubProvider.enqueue(.success(earlierReading))
        stubProvider.enqueue(.success(newerReading))
        stubProvider.enqueue(.success(newerReading))
        let monitor = makeMonitor()

        _ = await monitor.performFetch()
        _ = await monitor.performFetch()
        _ = await monitor.performFetch()

        #expect(monitor.previousReading == earlierReading)
        #expect(monitor.currentReading == newerReading)
    }

    @Test func failuresShowUnknownAndBackOff() async {
        stubProvider.enqueue(.success(makeReading(secondsBeforeReference: 30)))
        stubProvider.enqueue(.failure(GlucoseProviderError.networkUnavailable))
        stubProvider.enqueue(.failure(GlucoseProviderError.networkUnavailable))
        let monitor = makeMonitor()
        _ = await monitor.performFetch()

        let firstFailureDelay = await monitor.performFetch()
        let secondFailureDelay = await monitor.performFetch()

        #expect(monitor.displayState == .unknown(reason: GlucoseProviderError.networkUnavailable.statusMessage))
        #expect(monitor.currentReading != nil)
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
        #expect(monitor.displayState == .current(DisplayedReadings(currentReading: recoveredReading, previousReading: nil)))
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

    @Test func offlineSkipsFetchAndShowsNetworkUnavailable() async {
        stubConnectivityMonitor.setNetworkAvailable(false)
        let monitor = makeMonitor()

        let nextDelay = await monitor.performFetch()

        #expect(stubProvider.fetchCount == 0)
        #expect(monitor.displayState == .unknown(reason: GlucoseProviderError.networkUnavailable.statusMessage))
        #expect(nextDelay == GlucoseFetchScheduler.offlineRecheckInterval)
    }

    @Test func networkRestorationFetchesImmediately() async throws {
        let restoredReading = makeReading(secondsBeforeReference: 30)
        stubProvider.enqueue(.success(restoredReading))
        stubConnectivityMonitor.setNetworkAvailable(false)
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        try await waitUntil { monitor.lastFetchError == .networkUnavailable }
        #expect(stubProvider.fetchCount == 0)

        stubConnectivityMonitor.setNetworkAvailable(true)

        try await waitUntil { monitor.currentReading != nil }
        #expect(stubProvider.fetchCount == 1)
        #expect(monitor.displayState == .current(DisplayedReadings(currentReading: restoredReading, previousReading: nil)))
    }

    @Test func networkLossAloneDoesNotFetch() async throws {
        stubProvider.enqueue(.success(makeReading(secondsBeforeReference: 30)))
        let monitor = makeMonitor()
        monitor.start()
        defer { monitor.stop() }
        try await waitUntil { monitor.currentReading != nil }

        stubConnectivityMonitor.setNetworkAvailable(false)
        try await Task.sleep(for: .milliseconds(50))

        #expect(stubProvider.fetchCount == 1)
        #expect(monitor.lastFetchError == nil)
    }

    /// Polls a main-actor condition that background tasks of the monitor will make true.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    @Test func applyingNewSettingsClearsPreviousReading() async {
        stubProvider.enqueue(.success(makeReading(secondsBeforeReference: 330)))
        stubProvider.enqueue(.success(makeReading(secondsBeforeReference: 30)))
        let monitor = makeMonitor()
        _ = await monitor.performFetch()
        _ = await monitor.performFetch()
        #expect(monitor.previousReading != nil)

        monitor.resetProviderAndReadings()

        #expect(monitor.currentReading == nil)
        #expect(monitor.previousReading == nil)
        #expect(monitor.displayState == .unknown(reason: GlucoseReadingFreshness.awaitingFirstReadingReason))
    }
}
