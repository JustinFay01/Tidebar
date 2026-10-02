//
//  DiagnosticEventLog.swift
//  Tidebar
//

import Foundation
import os

/// Something that happened, recorded for diagnostics reports.
///
/// Redaction is by construction: every case carries only typed, non-sensitive values.
/// Never add usernames, passwords, account or session IDs, glucose values, reading
/// timestamps, or free-form text from servers (Dexcom error messages can echo account details).
nonisolated enum DiagnosticEventKind: Equatable, Sendable {
    case providerConfigured(providerName: String)
    case providerSetupFailed(diagnosticCode: TidebarDiagnosticCode)
    case refreshRequested
    case systemWoke
    case fetchStarted
    case fetchSucceeded(readingAgeSeconds: Int)
    case fetchFailed(diagnosticCode: TidebarDiagnosticCode)
    case nextFetchScheduled(delaySeconds: Int)
    case signInStarted
    case signInSucceeded
    case signInFailed(diagnosticCode: TidebarDiagnosticCode)
    case signInSkippedWhileBackingOff(diagnosticCode: TidebarDiagnosticCode)
    case sessionExpiredSigningInAgain
    case requestCompleted(requestName: String, httpStatusCode: Int, durationMilliseconds: Int, serverErrorCode: String?)
    case requestFailedInTransport(requestName: String, transportErrorCode: Int, durationMilliseconds: Int)
}

nonisolated struct DiagnosticEvent: Equatable, Sendable {
    let eventTimestamp: Date
    let eventKind: DiagnosticEventKind
}

nonisolated protocol DiagnosticEventRecording: Sendable {
    func record(_ eventKind: DiagnosticEventKind)
}

/// Records nothing; the default where diagnostics aren't wired up (e.g. most tests).
nonisolated struct DisabledDiagnosticEventRecorder: DiagnosticEventRecording {
    func record(_ eventKind: DiagnosticEventKind) {}
}

/// Keeps the most recent events in memory for diagnostics reports, and mirrors each one to the
/// macOS unified log (stored on the Mac by the system), so `log show --predicate
/// 'subsystem == "com.jnfcorp.Tidebar"'` works too. Events are redacted by construction either way.
nonisolated final class DiagnosticEventLog: DiagnosticEventRecording {
    static let defaultCapacity = 200

    private static let logger = Logger(subsystem: "com.jnfcorp.Tidebar", category: "Diagnostics")

    private let capacity: Int
    private let currentDateProvider: @Sendable () -> Date
    private let lockedEvents = OSAllocatedUnfairLock(initialState: [DiagnosticEvent]())

    init(capacity: Int = defaultCapacity, currentDateProvider: @escaping @Sendable () -> Date = { Date() }) {
        self.capacity = max(capacity, 1)
        self.currentDateProvider = currentDateProvider
    }

    /// Oldest first.
    var recentEvents: [DiagnosticEvent] {
        lockedEvents.withLock { $0 }
    }

    func record(_ eventKind: DiagnosticEventKind) {
        let newEvent = DiagnosticEvent(eventTimestamp: currentDateProvider(), eventKind: eventKind)
        lockedEvents.withLock { storedEvents in
            storedEvents.append(newEvent)
            if storedEvents.count > capacity {
                storedEvents.removeFirst(storedEvents.count - capacity)
            }
        }
        let eventDescription = DiagnosticEventDescriber.describe(eventKind)
        Self.logger.notice("\(eventDescription, privacy: .public)")
    }
}

/// Turns events into one-line text for reports and the system log.
nonisolated enum DiagnosticEventDescriber {
    static func describe(_ eventKind: DiagnosticEventKind) -> String {
        switch eventKind {
        case .providerConfigured(let providerName):
            return "Provider configured: \(providerName)"
        case .providerSetupFailed(let diagnosticCode):
            return "Provider not configured (\(diagnosticCode.rawValue))"
        case .refreshRequested:
            return "Refresh requested"
        case .systemWoke:
            return "Mac woke from sleep"
        case .fetchStarted:
            return "Fetch started"
        case .fetchSucceeded(let readingAgeSeconds):
            return "Fetch succeeded; latest reading \(formatSeconds(readingAgeSeconds)) old"
        case .fetchFailed(let diagnosticCode):
            return "Fetch failed (\(diagnosticCode.rawValue))"
        case .nextFetchScheduled(let delaySeconds):
            return "Next fetch in \(formatSeconds(delaySeconds))"
        case .signInStarted:
            return "Sign-in started"
        case .signInSucceeded:
            return "Sign-in succeeded"
        case .signInFailed(let diagnosticCode):
            return "Sign-in failed (\(diagnosticCode.rawValue))"
        case .signInSkippedWhileBackingOff(let diagnosticCode):
            return "Sign-in skipped while backing off after \(diagnosticCode.rawValue)"
        case .sessionExpiredSigningInAgain:
            return "Session expired; signing in again"
        case .requestCompleted(let requestName, let httpStatusCode, let durationMilliseconds, let serverErrorCode):
            let serverErrorSuffix = serverErrorCode.map { ", code \($0)" } ?? ""
            return "\(requestName) → HTTP \(httpStatusCode)\(serverErrorSuffix) (\(durationMilliseconds) ms)"
        case .requestFailedInTransport(let requestName, let transportErrorCode, let durationMilliseconds):
            return "\(requestName) → network error \(transportErrorCode) (\(durationMilliseconds) ms)"
        }
    }

    /// e.g. `45s`, `5m 15s`, `2h 3m`
    static func formatSeconds(_ totalSeconds: Int) -> String {
        let nonNegativeSeconds = max(totalSeconds, 0)
        let hours = nonNegativeSeconds / 3600
        let minutes = (nonNegativeSeconds % 3600) / 60
        let seconds = nonNegativeSeconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
