//
//  GlucoseProvider.swift
//  Tidebar
//

import Foundation

/// A source of glucose readings. Providers normalize their own wire format and auth lifecycle,
/// and map every failure to `GlucoseProviderError`. They contain no polling, staleness, unit, or formatting logic.
nonisolated protocol GlucoseProvider: Sendable {
    var providerDisplayName: String { get }
    func fetchLatestReading() async throws -> GlucoseReading
    func fetchRecentReadings(withinMinutes lookbackMinutes: Int) async throws -> [GlucoseReading]
}

nonisolated enum GlucoseProviderError: Error, Equatable, Sendable {
    case invalidCredentials
    case networkUnavailable
    case noRecentReadings
    case accountLockedOrRateLimited
    case unexpectedResponse(description: String)

    var userFacingDescription: String {
        switch self {
        case .invalidCredentials:
            "Sign-in failed. Check your username, password, and region in Settings."
        case .networkUnavailable:
            "Network unavailable."
        case .noRecentReadings:
            "No readings found. Make sure Share is enabled in the Dexcom app with at least one follower."
        case .accountLockedOrRateLimited:
            "Too many sign-in attempts. The account may be temporarily locked; Tidebar will retry later."
        case .unexpectedResponse(let description):
            "Unexpected response: \(description)"
        }
    }
}

extension GlucoseProviderError: LocalizedError {
    nonisolated var errorDescription: String? { userFacingDescription }
}
