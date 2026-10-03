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
        providerSetupError?.statusMessage ?? lastFetchError?.statusMessage
    }

    /// The code for whatever is currently wrong, or `nil` when the display is healthy.
    var currentDiagnosticCode: TidebarDiagnosticCode? {
        if let providerSetupError {
            return providerSetupError.diagnosticCode
        }
        if let lastFetchError {
            return lastFetchError.diagnosticCode
        }
        if let latestReading, GlucoseReadingFreshness.isStale(latestReading, at: displayEvaluationDate) {
            return .readingStale
        }
        return nil
    }

    /// Monitor state for diagnostics reports. Contains no glucose values or reading timestamps.
    var diagnosticsStatus: GlucoseMonitorDiagnosticsStatus {
        let currentDate = currentDateProvider()
        return GlucoseMonitorDiagnosticsStatus(
            displayStateKind: GlucoseMonitorDiagnosticsStatus.DisplayStateKind(displayState),
            currentDiagnosticCode: currentDiagnosticCode,
            providerDisplayName: providerDisplayName,
            latestReadingAgeSeconds: latestReading.map { Int(GlucoseReadingFreshness.readingAge(of: $0, at: currentDate)) },
            secondsSinceLastSuccessfulFetch: lastSuccessfulFetchDate.map { Int(currentDate.timeIntervalSince($0)) },
            consecutiveFetchFailureCount: consecutiveFetchFailureCount,
            isFetchInProgress: isFetchInProgress
        )
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
    @ObservationIgnored private let diagnosticEventRecorder: any DiagnosticEventRecording
    @ObservationIgnored private let networkConnectivityMonitor: any NetworkConnectivityMonitoring
    @ObservationIgnored private var glucoseProvider: (any GlucoseProvider)?
    /// Incremented whenever the provider is replaced, so results from an older provider are discarded.
    @ObservationIgnored private var providerGeneration = 0
    @ObservationIgnored private var consecutiveFetchFailureCount = 0
    @ObservationIgnored private var isProviderSetupRetryPending = false
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var displayRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var systemWakeObservationTask: Task<Void, Never>?
    @ObservationIgnored private var networkConnectivityObservationTask: Task<Void, Never>?

    init(
        providerBuilder: @escaping GlucoseProviderBuilder,
        currentDateProvider: @escaping () -> Date = { Date() },
        sleepFunction: @escaping SleepFunction = { delaySeconds in try await Task.sleep(for: .seconds(delaySeconds)) },
        diagnosticEventRecorder: any DiagnosticEventRecording = DisabledDiagnosticEventRecorder(),
        networkConnectivityMonitor: any NetworkConnectivityMonitoring = AlwaysAvailableNetworkConnectivityMonitor()
    ) {
        self.providerBuilder = providerBuilder
        self.currentDateProvider = currentDateProvider
        self.sleepFunction = sleepFunction
        self.diagnosticEventRecorder = diagnosticEventRecorder
        self.networkConnectivityMonitor = networkConnectivityMonitor
        self.displayEvaluationDate = currentDateProvider()
    }

    // MARK: - Lifecycle

    /// Builds the provider from saved settings, fetches immediately, and keeps polling.
    func start() {
        guard pollingTask == nil else {
            return
        }
        rebuildProvider()
        // Subscribe before the first fetch so a restoration right after an offline skip isn't missed.
        startObservingNetworkConnectivity()
        restartPolling()
        startDisplayRefreshLoop()
        startObservingSystemWake()
    }

    func stop() {
        pollingTask?.cancel()
        displayRefreshTask?.cancel()
        systemWakeObservationTask?.cancel()
        networkConnectivityObservationTask?.cancel()
        pollingTask = nil
        displayRefreshTask = nil
        systemWakeObservationTask = nil
        networkConnectivityObservationTask = nil
    }

    /// Fetches now and restarts the schedule from the result.
    func refreshNow() {
        diagnosticEventRecorder.record(.refreshRequested)
        restartPolling()
    }

    /// Call when the provider should change (account settings saved, or a debug simulation chosen):
    /// discards the old provider and its data, then fetches.
    func rebuildProviderAndRefresh() {
        resetProviderAndReadings()
        restartPolling()
    }

    /// Rebuilds the provider and discards its data without fetching or starting the polling loop.
    /// Tests use this to drive `performFetch()` directly, without a background fetch racing them.
    func resetProviderAndReadings() {
        rebuildProvider()
        latestReading = nil
        lastFetchError = nil
        lastSuccessfulFetchDate = nil
        consecutiveFetchFailureCount = 0
    }

    func updateDisplayEvaluationDate() {
        displayEvaluationDate = currentDateProvider()
    }

    // MARK: - Fetching

    /// Performs one fetch and returns the delay before the next, or `nil` when polling should stop
    /// (no provider configured, or the fetch was cancelled).
    func performFetch() async -> TimeInterval? {
        if isProviderSetupRetryPending {
            isProviderSetupRetryPending = false
            rebuildProvider()
        }
        guard let glucoseProvider else {
            return scheduleProviderSetupRetryIfRecoverable()
        }
        guard networkConnectivityMonitor.isNetworkAvailable else {
            return skipFetchWhileOffline()
        }
        let fetchProviderGeneration = providerGeneration
        activeFetchCount += 1
        defer { activeFetchCount -= 1 }
        diagnosticEventRecorder.record(.fetchStarted)

        do {
            let fetchedReading = try await glucoseProvider.fetchLatestReading()
            guard fetchProviderGeneration == providerGeneration else {
                return nil
            }
            recordSuccessfulFetch(fetchedReading)
            let delayUntilNextFetch = GlucoseFetchScheduler.delayAfterSuccessfulFetch(
                latestReadingTimestamp: fetchedReading.readingTimestamp,
                currentDate: currentDateProvider()
            )
            diagnosticEventRecorder.record(.nextFetchScheduled(delaySeconds: Int(delayUntilNextFetch)))
            return delayUntilNextFetch
        } catch {
            guard fetchProviderGeneration == providerGeneration,
                !Self.isCancellation(error),
                !Task.isCancelled
            else {
                return nil
            }
            let fetchFailure = Self.normalizeFetchError(error)
            recordFailedFetch(fetchFailure)
            let delayUntilNextFetch = GlucoseFetchScheduler.delayAfterFailedFetch(
                fetchFailure: fetchFailure,
                consecutiveFailureCount: consecutiveFetchFailureCount
            )
            diagnosticEventRecorder.record(.nextFetchScheduled(delaySeconds: Int(delayUntilNextFetch)))
            return delayUntilNextFetch
        }
    }

    /// A missing account or password needs the user, so polling stops. An unreadable password can
    /// fix itself (the Keychain unlocks), so the provider is rebuilt on the next pass.
    private func scheduleProviderSetupRetryIfRecoverable() -> TimeInterval? {
        guard case .passwordUnreadable = providerSetupError else {
            return nil
        }
        isProviderSetupRetryPending = true
        diagnosticEventRecorder.record(.nextFetchScheduled(delaySeconds: Int(GlucoseFetchScheduler.providerSetupRetryInterval)))
        return GlucoseFetchScheduler.providerSetupRetryInterval
    }

    /// Shows the network problem without contacting the provider. The connectivity observer fetches
    /// as soon as the network returns; the returned delay is only a fallback re-check.
    private func skipFetchWhileOffline() -> TimeInterval {
        diagnosticEventRecorder.record(.fetchSkippedWhileOffline)
        lastFetchError = .networkUnavailable
        updateDisplayEvaluationDate()
        return GlucoseFetchScheduler.offlineRecheckInterval
    }

    private func recordSuccessfulFetch(_ fetchedReading: GlucoseReading) {
        let readingAgeSeconds = GlucoseReadingFreshness.readingAge(of: fetchedReading, at: currentDateProvider())
        diagnosticEventRecorder.record(.fetchSucceeded(readingAgeSeconds: Int(readingAgeSeconds)))
        latestReading = fetchedReading
        lastFetchError = nil
        consecutiveFetchFailureCount = 0
        lastSuccessfulFetchDate = currentDateProvider()
        updateDisplayEvaluationDate()
    }

    private func recordFailedFetch(_ fetchFailure: GlucoseProviderError) {
        diagnosticEventRecorder.record(.fetchFailed(diagnosticCode: fetchFailure.diagnosticCode))
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
        isProviderSetupRetryPending = false
        switch providerBuilder() {
        case .success(let builtProvider):
            glucoseProvider = builtProvider
            providerDisplayName = builtProvider.providerDisplayName
            providerSetupError = nil
            diagnosticEventRecorder.record(.providerConfigured(providerName: builtProvider.providerDisplayName))
        case .failure(let setupError):
            glucoseProvider = nil
            providerDisplayName = nil
            providerSetupError = setupError
            diagnosticEventRecorder.record(.providerSetupFailed(diagnosticCode: setupError.diagnosticCode))
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
                self?.recordSystemWakeAndRefresh()
            }
        }
    }

    private func recordSystemWakeAndRefresh() {
        diagnosticEventRecorder.record(.systemWoke)
        refreshNow()
    }

    private func startObservingNetworkConnectivity() {
        networkConnectivityObservationTask?.cancel()
        let connectivityChanges = networkConnectivityMonitor.connectivityChanges()
        networkConnectivityObservationTask = Task { [weak self] in
            for await isNetworkAvailable in connectivityChanges {
                self?.handleNetworkConnectivityChange(isNetworkAvailable: isNetworkAvailable)
            }
        }
    }

    private func handleNetworkConnectivityChange(isNetworkAvailable: Bool) {
        guard isNetworkAvailable else {
            diagnosticEventRecorder.record(.networkLost)
            return
        }
        diagnosticEventRecorder.record(.networkRestored)
        // Start the backoff over: a failure right after reconnecting should retry quickly.
        consecutiveFetchFailureCount = 0
        refreshNow()
    }
}
