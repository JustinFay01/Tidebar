//
//  GlucoseFetchScheduler.swift
//  Tidebar
//

import Foundation

/// Computes when to fetch next. G7 sensors publish a reading every 5 minutes.
nonisolated enum GlucoseFetchScheduler {
    static let sensorReadingInterval: TimeInterval = 5 * 60
    /// Extra time for the reading to reach the Share servers after the sensor records it.
    static let readingPublicationGracePeriod: TimeInterval = 15
    static let awaitingNewReadingRetryInterval: TimeInterval = 60
    static let initialFailureRetryInterval: TimeInterval = 15
    static let maximumFailureRetryInterval: TimeInterval = 5 * 60
    /// How often connectivity is re-checked while offline, in case the restoration notification never arrives.
    static let offlineRecheckInterval: TimeInterval = 60

    /// Waits until the next reading is expected; if it is already overdue, polls every minute.
    static func delayAfterSuccessfulFetch(latestReadingTimestamp: Date, currentDate: Date) -> TimeInterval {
        let expectedNextReadingDate =
            latestReadingTimestamp
            .addingTimeInterval(sensorReadingInterval + readingPublicationGracePeriod)
        let secondsUntilExpectedNextReading = expectedNextReadingDate.timeIntervalSince(currentDate)
        guard secondsUntilExpectedNextReading > 0 else {
            return awaitingNewReadingRetryInterval
        }
        return min(secondsUntilExpectedNextReading, sensorReadingInterval + readingPublicationGracePeriod)
    }

    /// Exponential backoff capped at about five minutes. Account problems wait the full cap straight away.
    static func delayAfterFailedFetch(fetchFailure: GlucoseProviderError, consecutiveFailureCount: Int) -> TimeInterval {
        switch fetchFailure {
        case .invalidCredentials, .accountLockedOrRateLimited:
            return maximumFailureRetryInterval
        case .networkUnavailable, .noRecentReadings, .unexpectedResponse:
            let backoffExponent = Double(max(consecutiveFailureCount - 1, 0))
            return min(initialFailureRetryInterval * pow(2, backoffExponent), maximumFailureRetryInterval)
        }
    }
}
