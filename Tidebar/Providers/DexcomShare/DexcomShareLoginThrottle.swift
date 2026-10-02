//
//  DexcomShareLoginThrottle.swift
//  Tidebar
//

import Foundation

/// Guards the Share login endpoints. Dexcom locks accounts after too many failed sign-ins, so:
/// - rejected credentials stop all further login attempts until a new provider is built (i.e. Settings change);
/// - other failures that reached Dexcom back off exponentially;
/// - network failures never reached Dexcom and are not throttled here.
nonisolated struct DexcomShareLoginThrottle: Sendable {
    static let initialLoginBackoffInterval: TimeInterval = 30
    static let maximumLoginBackoffInterval: TimeInterval = 15 * 60

    private(set) var consecutiveLoginFailureCount = 0
    private(set) var earliestNextLoginAttemptDate: Date?
    private(set) var mostRecentLoginFailure: GlucoseProviderError?
    private(set) var hasRejectedCredentials = false

    /// The error to surface instead of attempting a login, or `nil` when a login attempt is allowed.
    func errorPreventingLoginAttempt(at currentDate: Date) -> GlucoseProviderError? {
        if hasRejectedCredentials {
            return .invalidCredentials
        }
        if let earliestNextLoginAttemptDate, currentDate < earliestNextLoginAttemptDate {
            return mostRecentLoginFailure ?? .accountLockedOrRateLimited
        }
        return nil
    }

    mutating func recordLoginSuccess() {
        consecutiveLoginFailureCount = 0
        earliestNextLoginAttemptDate = nil
        mostRecentLoginFailure = nil
    }

    mutating func recordLoginFailure(_ loginFailure: GlucoseProviderError, at currentDate: Date) {
        guard loginFailure != .networkUnavailable else {
            return
        }
        consecutiveLoginFailureCount += 1
        mostRecentLoginFailure = loginFailure
        if loginFailure == .invalidCredentials {
            hasRejectedCredentials = true
        }
        let backoffInterval = Self.loginBackoffInterval(
            afterFailure: loginFailure,
            consecutiveLoginFailureCount: consecutiveLoginFailureCount
        )
        earliestNextLoginAttemptDate = currentDate.addingTimeInterval(backoffInterval)
    }

    static func loginBackoffInterval(
        afterFailure loginFailure: GlucoseProviderError,
        consecutiveLoginFailureCount: Int
    ) -> TimeInterval {
        if loginFailure == .accountLockedOrRateLimited {
            return maximumLoginBackoffInterval
        }
        let backoffExponent = Double(max(consecutiveLoginFailureCount - 1, 0))
        return min(initialLoginBackoffInterval * pow(2, backoffExponent), maximumLoginBackoffInterval)
    }
}
