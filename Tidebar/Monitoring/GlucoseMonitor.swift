//
//  GlucoseMonitor.swift
//  Tidebar
//

import AppKit
import Foundation
import Observation

/// Owns the active provider, polls it on the G7 cadence, and publishes what the UI should show.
@MainActor
@Observable
final class GlucoseMonitor {
    typealias GlucoseProviderBuilder = @MainActor () -> Result<any GlucoseProvider, GlucoseProviderSetupError>
    typealias SleepFunction = @Sendable (TimeInterval) async throws -> Void

    /// How often the display state is re-evaluated so readings age without waiting for a fetch.
    static let displayRefreshInterval: TimeInterval = 15

    private(set) var latestReading: GlucoseReading?
    private(set) var lastFetchError: GlucoseProviderError?
    private(set) var providerSetupError: GlucoseProviderSetupError?
    private(set) var providerDisplayName: String?
    private(set) var lastSuccessfulFetchDate: Date?
    private(set) var displayEvaluationDate: Date
    private var activeFetchCount = 0

    var isFetchInProgress: Bool {
        activeFetchCount > 0
    }

    /// Why no value can be shown right now, if anything prevents it.
    var unavailableReason: String? {
        providerSetupError?.userFacingDescription ?? lastFetchError?.userFacingDescription
    }

    var displayState: GlucoseDisplayState {
        GlucoseReadingFreshness.classifyDisplayState(
            latestReading: latestReading,
            unavailableReason: unavailableReason,
            currentDate: displayEvaluationDate
        )
    }

    @ObservationIgnored private let providerBuilder: GlucoseProviderBuilder
    @ObservationIgnored private let currentDateProvider: () -> Date
    @ObservationIgnored private let sleepFunction: SleepFunction
    @ObservationIgnored private var glucoseProvider: (any GlucoseProvider)?
    /// Incremented whenever the provider is replaced, so results from an older provider are discarded.
    @ObservationIgnored private var providerGeneration = 0
    @ObservationIgnored private var consecutiveFetchFailureCount = 0
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var displayRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var systemWakeObservationTask: Task<Void, Never>?

    init(
        providerBuilder: @escaping GlucoseProviderBuilder,
        currentDateProvider: @escaping () -> Date = { Date() },
        sleepFunction: @escaping SleepFunction = { delaySeconds in try await Task.sleep(for: .seconds(delaySeconds)) }
    ) {
        self.providerBuilder = providerBuilder
        self.currentDateProvider = currentDateProvider
        self.sleepFunction = sleepFunction
        self.displayEvaluationDate = currentDateProvider()
    }

    // MARK: - Lifecycle

    /// Builds the provider from saved settings, fetches immediately, and keeps polling.
    func start() {
        guard pollingTask == nil else {
            return
        }
        rebuildProvider()
        restartPolling()
        startDisplayRefreshLoop()
        startObservingSystemWake()
    }

    func stop() {
        pollingTask?.cancel()
        displayRefreshTask?.cancel()
        systemWakeObservationTask?.cancel()
        pollingTask = nil
        displayRefreshTask = nil
        systemWakeObservationTask = nil
    }

    /// Fetches now and restarts the schedule from the result.
    func refreshNow() {
        restartPolling()
    }

    /// Call when the provider should change (account settings saved, or a debug simulation chosen):
    /// discards the old provider and its data, then fetches.
    func rebuildProviderAndRefresh() {
        rebuildProvider()
        latestReading = nil
        lastFetchError = nil
        lastSuccessfulFetchDate = nil
        consecutiveFetchFailureCount = 0
        restartPolling()
    }

    func updateDisplayEvaluationDate() {
        displayEvaluationDate = currentDateProvider()
    }

    // MARK: - Fetching

    /// Performs one fetch and returns the delay before the next, or `nil` when polling should stop
    /// (no provider configured, or the fetch was cancelled).
    func performFetch() async -> TimeInterval? {
        guard let glucoseProvider else {
            return nil
        }
        let fetchProviderGeneration = providerGeneration
        activeFetchCount += 1
        defer { activeFetchCount -= 1 }

        do {
            let fetchedReading = try await glucoseProvider.fetchLatestReading()
            guard fetchProviderGeneration == providerGeneration else {
                return nil
            }
            recordSuccessfulFetch(fetchedReading)
            return GlucoseFetchScheduler.delayAfterSuccessfulFetch(
                latestReadingTimestamp: fetchedReading.readingTimestamp,
                currentDate: currentDateProvider()
            )
        } catch {
            guard fetchProviderGeneration == providerGeneration,
                  !Self.isCancellation(error),
                  !Task.isCancelled
            else {
                return nil
            }
            let fetchFailure = Self.normalizeFetchError(error)
            recordFailedFetch(fetchFailure)
            return GlucoseFetchScheduler.delayAfterFailedFetch(
                fetchFailure: fetchFailure,
                consecutiveFailureCount: consecutiveFetchFailureCount
            )
        }
    }

    private func recordSuccessfulFetch(_ fetchedReading: GlucoseReading) {
        latestReading = fetchedReading
        lastFetchError = nil
        consecutiveFetchFailureCount = 0
        lastSuccessfulFetchDate = currentDateProvider()
        updateDisplayEvaluationDate()
    }

    private func recordFailedFetch(_ fetchFailure: GlucoseProviderError) {
        lastFetchError = fetchFailure
        consecutiveFetchFailureCount += 1
        updateDisplayEvaluationDate()
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
    }

    private static func normalizeFetchError(_ error: Error) -> GlucoseProviderError {
        (error as? GlucoseProviderError) ?? .unexpectedResponse(description: error.localizedDescription)
    }

    // MARK: - Provider

    private func rebuildProvider() {
        providerGeneration += 1
        switch providerBuilder() {
        case .success(let builtProvider):
            glucoseProvider = builtProvider
            providerDisplayName = builtProvider.providerDisplayName
            providerSetupError = nil
        case .failure(let setupError):
            glucoseProvider = nil
            providerDisplayName = nil
            providerSetupError = setupError
        }
        updateDisplayEvaluationDate()
    }

    // MARK: - Background loops

    private func restartPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
    }

    private func runPollingLoop() async {
        while !Task.isCancelled {
            guard let delayUntilNextFetch = await performFetch() else {
                return
            }
            do {
                try await sleepFunction(delayUntilNextFetch)
            } catch {
                return
            }
        }
    }

    private func startDisplayRefreshLoop() {
        displayRefreshTask?.cancel()
        displayRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.displayRefreshInterval))
                } catch {
                    return
                }
                self?.updateDisplayEvaluationDate()
            }
        }
    }

    private func startObservingSystemWake() {
        systemWakeObservationTask?.cancel()
        systemWakeObservationTask = Task { [weak self] in
            let wakeNotifications = NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification)
            for await _ in wakeNotifications {
                self?.refreshNow()
            }
        }
    }
}
