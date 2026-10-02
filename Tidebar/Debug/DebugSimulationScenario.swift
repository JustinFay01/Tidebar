//
//  DebugSimulationScenario.swift
//  Tidebar
//

#if DEBUG
import Foundation

/// Situations the Debug menu can simulate without contacting any server.
nonisolated enum DebugSimulationScenario: String, CaseIterable, Identifiable, Sendable {
    case liveData

    case invalidCredentials
    case networkUnavailable
    case noRecentReadings
    case accountLockedOrRateLimited
    case unexpectedResponse

    case currentReading
    case agingReading
    case staleReading
    case doubleUpTrend
    case doubleDownTrend
    case indeterminateTrend

    static let simulatedValueMgPerDeciliter = 112
    static let agingReadingAgeSeconds: TimeInterval = 8 * 60
    static let staleReadingAgeSeconds: TimeInterval = 20 * 60

    static let errorScenarios: [DebugSimulationScenario] = [
        .invalidCredentials, .networkUnavailable, .noRecentReadings, .accountLockedOrRateLimited, .unexpectedResponse,
    ]

    static let readingScenarios: [DebugSimulationScenario] = [
        .currentReading, .agingReading, .staleReading, .doubleUpTrend, .doubleDownTrend, .indeterminateTrend,
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
        case .currentReading: "Current Reading"
        case .agingReading: "Aging Reading (8 min)"
        case .staleReading: "Stale Reading (20 min)"
        case .doubleUpTrend: "Rising Quickly"
        case .doubleDownTrend: "Falling Quickly"
        case .indeterminateTrend: "No Trend Available"
        }
    }

    /// The fetch result this scenario produces, or `nil` for live data.
    func simulatedOutcome(at currentDate: Date) -> Result<GlucoseReading, GlucoseProviderError>? {
        switch self {
        case .liveData:
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
        case .currentReading:
            return .success(Self.makeSimulatedReading(trendDirection: .flat, ageSeconds: 0, currentDate: currentDate))
        case .agingReading:
            let agingAgeSeconds = Self.agingReadingAgeSeconds
            return .success(Self.makeSimulatedReading(trendDirection: .flat, ageSeconds: agingAgeSeconds, currentDate: currentDate))
        case .staleReading:
            let staleAgeSeconds = Self.staleReadingAgeSeconds
            return .success(Self.makeSimulatedReading(trendDirection: .flat, ageSeconds: staleAgeSeconds, currentDate: currentDate))
        case .doubleUpTrend:
            return .success(Self.makeSimulatedReading(trendDirection: .doubleUp, ageSeconds: 0, currentDate: currentDate))
        case .doubleDownTrend:
            return .success(Self.makeSimulatedReading(trendDirection: .doubleDown, ageSeconds: 0, currentDate: currentDate))
        case .indeterminateTrend:
            return .success(Self.makeSimulatedReading(trendDirection: .notComputable, ageSeconds: 0, currentDate: currentDate))
        }
    }

    private static func makeSimulatedReading(
        trendDirection: TrendDirection,
        ageSeconds: TimeInterval,
        currentDate: Date
    ) -> GlucoseReading {
        GlucoseReading(
            valueMgPerDeciliter: simulatedValueMgPerDeciliter,
            trendDirection: trendDirection,
            readingTimestamp: currentDate.addingTimeInterval(-ageSeconds)
        )
    }
}
#endif
