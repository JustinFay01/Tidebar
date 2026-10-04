//
//  TidebarDiagnosticCode.swift
//  Tidebar
//

import Foundation

/// Short, stable codes shown next to problems in the UI and in diagnostics reports, so users can
/// search existing issues and reports can be grouped. Never renumber a code once released;
/// add new ones instead. Keep the README's troubleshooting table in sync.
nonisolated enum TidebarDiagnosticCode: String, CaseIterable, Sendable {
    case signInRejected = "AUTH-01"
    case accountLockedOrRateLimited = "AUTH-02"
    case networkUnavailable = "NET-01"
    case noReadingsShared = "DATA-01"
    case readingStale = "DATA-02"
    case unexpectedServerResponse = "SRV-01"
    case accountNotConfigured = "SETUP-01"
    case passwordMissing = "SETUP-02"
    case passwordUnreadable = "SETUP-03"

    /// One-line meaning, used in diagnostics reports.
    var summary: String {
        switch self {
        case .signInRejected: "Dexcom rejected the username, password, or region"
        case .accountLockedOrRateLimited: "Too many sign-in attempts; account locked or rate limited"
        case .networkUnavailable: "Could not reach Dexcom"
        case .noReadingsShared: "Signed in, but Dexcom returned no readings"
        case .readingStale: "Latest reading is more than 12 minutes old"
        case .unexpectedServerResponse: "Dexcom returned an error or a response Tidebar didn't understand"
        case .accountNotConfigured: "No Dexcom account set up"
        case .passwordMissing: "No password saved"
        case .passwordUnreadable: "Keychain refused to return the saved password"
        }
    }

    /// Appends the code to a user-facing message, e.g. "Network unavailable. (NET-01)".
    func appended(to userFacingMessage: String) -> String {
        "\(userFacingMessage) (\(rawValue))"
    }
}

extension GlucoseProviderError {
    nonisolated var diagnosticCode: TidebarDiagnosticCode {
        switch self {
        case .invalidCredentials: .signInRejected
        case .networkUnavailable: .networkUnavailable
        case .noRecentReadings: .noReadingsShared
        case .accountLockedOrRateLimited: .accountLockedOrRateLimited
        case .unexpectedResponse: .unexpectedServerResponse
        }
    }

    /// The message shown in the UI, including its diagnostic code.
    nonisolated var statusMessage: String {
        diagnosticCode.appended(to: userFacingDescription)
    }
}

extension GlucoseProviderSetupError {
    nonisolated var diagnosticCode: TidebarDiagnosticCode {
        switch self {
        case .missingConfiguration: .accountNotConfigured
        case .missingPassword: .passwordMissing
        case .passwordUnreadable: .passwordUnreadable
        }
    }

    /// The message shown in the UI, including its diagnostic code.
    nonisolated var statusMessage: String {
        diagnosticCode.appended(to: userFacingDescription)
    }
}
