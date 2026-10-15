//
//  DebugSimulationScenario.swift
//  Tidebar
//

#if DEBUG
import Foundation
import Security

/// Situations the Debug menu can simulate without contacting any server.
nonisolated enum DebugSimulationScenario: String, CaseIterable, Identifiable, Sendable {
    case liveData

    case invalidCredentials
    case networkUnavailable
    case noRecentReadings
    case accountLockedOrRateLimited
    case unexpectedResponse

    case keychainUnreadable
    case keychainUnreadableUntilRetry

    case currentReading
    case agingReading
    case staleReading
    case singleUpTrend
    case singleDownTrend
    case doubleUpTrend
    case doubleDownTrend
    case indeterminateTrend

    static let simulatedValueMgPerDeciliter = 112
    static let agingReadingAgeSeconds: TimeInterval = 8 * 60
    static let staleReadingAgeSeconds: TimeInterval = 20 * 60
    /// Dexcom reports values in this range, so drifting readings stop at its ends.
    static let simulatedValueRangeMgPerDeciliter = 40...400

    static let errorScenarios: [DebugSimulationScenario] = [
        .invalidCredentials, .networkUnavailable, .noRecentReadings, .accountLockedOrRateLimited, .unexpectedResponse,
    ]

    /// Fail while building the provider, before any fetch, as a real Keychain failure would.
    static let setupScenarios: [DebugSimulationScenario] = [.keychainUnreadable, .keychainUnreadableUntilRetry]

    static let readingScenarios: [DebugSimulationScenario] = [
        .currentReading, .agingReading, .staleReading, .singleUpTrend, .singleDownTrend, .doubleUpTrend, .doubleDownTrend,
        .indeterminateTrend,
    ]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .liveData: "Live Data"
        case .invalidCredentials: "Invalid Credentials"
        case .networkUnavailable: "Network Unavailable"
        case .noRecentReadings: "No Readings (Share Disabled)"
        case .accountLockedOrRateLimited: "Account Locked / Rate Limited"
        case .unexpectedResponse: "Unexpected Server Response"
        case .keychainUnreadable: "Keychain Unreadable"
        case .keychainUnreadableUntilRetry: "Keychain Unreadable, Then Recovers"
        case .currentReading: "Current Reading"
        case .agingReading: "Aging Reading (8 min)"
        case .staleReading: "Stale Reading (20 min)"
        case .singleUpTrend: "Rising"
        case .singleDownTrend: "Falling"
        case .doubleUpTrend: "Rising Quickly"
        case .doubleDownTrend: "Falling Quickly"
        case .indeterminateTrend: "No Trend Available"
        }
    }

    /// The setup failure this scenario produces instead of a provider, or `nil` when a provider is built.
    /// Uses the status a locked keychain returns.
    var simulatedSetupError: GlucoseProviderSetupError? {
        switch self {
        case .keychainUnreadable, .keychainUnreadableUntilRetry:
            .passwordUnreadable(keychainFailure: KeychainOperationError(operationStatus: errSecInteractionNotAllowed))
        default:
            nil
        }
    }

    /// The fetch result this scenario produces, or `nil` for live data and for setup scenarios,
    /// which never get as far as a fetch.
    /// - Parameters:
    ///   - fetchIndex: how many fetches this scenario's provider has already answered.
    ///   - firstFetchDate: when this scenario's provider answered its first fetch.
    func simulatedOutcome(
        at currentDate: Date,
        fetchIndex: Int,
        firstFetchDate: Date
    ) -> Result<GlucoseReading, GlucoseProviderError>? {
        switch self {
        case .liveData, .keychainUnreadable, .keychainUnreadableUntilRetry:
            return nil
        case .invalidCredentials:
            return .failure(.invalidCredentials)
        case .networkUnavailable:
            return .failure(.networkUnavailable)
        case .noRecentReadings:
            return .failure(.noRecentReadings)
        case .accountLockedOrRateLimited:
            return .failure(.accountLockedOrRateLimited)
        case .unexpectedResponse:
            return .failure(.unexpectedResponse(description: "Simulated server error."))
        case .currentReading, .agingReading, .staleReading, .singleUpTrend, .singleDownTrend, .doubleUpTrend, .doubleDownTrend,
            .indeterminateTrend:
            return .success(makeSimulatedReading(at: currentDate, fetchIndex: fetchIndex, firstFetchDate: firstFetchDate))
        }
    }

    /// How much each simulated reading moves from the one before, or `nil` for a single unchanging reading.
    /// Aging and stale readings have none: the reading before them would already be stale,
    /// so the first fetch would show `---` before the real scenario.
    var simulatedChangePerReadingMgPerDeciliter: Int? {
        switch self {
        case .currentReading, .indeterminateTrend: 0
        case .singleUpTrend: 8
        case .singleDownTrend: -8
        case .doubleUpTrend: 18
        case .doubleDownTrend: -18
        default: nil
        }
    }

    private var simulatedTrendDirection: TrendDirection {
        switch self {
        case .singleUpTrend: .singleUp
        case .singleDownTrend: .singleDown
        case .doubleUpTrend: .doubleUp
        case .doubleDownTrend: .doubleDown
        case .indeterminateTrend: .notComputable
        default: .flat
        }
    }

    private var simulatedReadingAgeSeconds: TimeInterval {
        switch self {
        case .agingReading: Self.agingReadingAgeSeconds
        case .staleReading: Self.staleReadingAgeSeconds
        default: 0
        }
    }

    /// With a change per reading, the first fetch returns the reading from one sensor interval earlier,
    /// so the monitor has a previous reading to compare against; each later fetch returns a new reading
    /// that has moved by the change again, so the change keeps showing.
    /// Without one, every fetch returns the same reading, timestamped from the first fetch, as a sensor
    /// that stopped uploading would; a refresh then isn't mistaken for a new reading.
    private func makeSimulatedReading(at currentDate: Date, fetchIndex: Int, firstFetchDate: Date) -> GlucoseReading {
        guard let changePerReading = simulatedChangePerReadingMgPerDeciliter else {
            return makeSimulatedReading(
                valueMgPerDeciliter: Self.simulatedValueMgPerDeciliter,
                readingTimestamp: firstFetchDate.addingTimeInterval(-simulatedReadingAgeSeconds)
            )
        }
        if fetchIndex == 0 {
            return makeSimulatedReading(
                valueMgPerDeciliter: Self.simulatedValueMgPerDeciliter - changePerReading,
                readingTimestamp: currentDate.addingTimeInterval(-GlucoseFetchScheduler.sensorReadingInterval)
            )
        }
        return makeSimulatedReading(
            valueMgPerDeciliter: Self.simulatedValueMgPerDeciliter + changePerReading * (fetchIndex - 1),
            readingTimestamp: currentDate
        )
    }

    private func makeSimulatedReading(valueMgPerDeciliter: Int, readingTimestamp: Date) -> GlucoseReading {
        let valueRange = Self.simulatedValueRangeMgPerDeciliter
        return GlucoseReading(
            valueMgPerDeciliter: min(max(valueMgPerDeciliter, valueRange.lowerBound), valueRange.upperBound),
            trendDirection: simulatedTrendDirection,
            readingTimestamp: readingTimestamp
        )
    }
}
#endif
