//
//  GlucoseDisplayState.swift
//  Tidebar
//

import Foundation

nonisolated enum GlucoseDisplayState: Equatable, Sendable {
    case unknown(reason: String)
    case current(GlucoseReading)
    case aging(GlucoseReading)
}

/// Decides whether a reading is fresh enough to show.
nonisolated enum GlucoseReadingFreshness {
    /// Readings at least this old are shown dimmed with an age suffix.
    static let agingThresholdSeconds: TimeInterval = 6 * 60
    /// Readings older than this are not shown at all.
    static let staleThresholdSeconds: TimeInterval = 12 * 60

    static let awaitingFirstReadingReason = "Waiting for the first reading…"

    /// - Parameter unavailableReason: set when credentials are missing or the latest fetch failed;
    ///   either makes the state unknown regardless of any earlier reading.
    static func classifyDisplayState(
        latestReading: GlucoseReading?,
        unavailableReason: String?,
        currentDate: Date
    ) -> GlucoseDisplayState {
        if let unavailableReason {
            return .unknown(reason: unavailableReason)
        }
        guard let latestReading else {
            return .unknown(reason: awaitingFirstReadingReason)
        }
        let readingAgeSeconds = readingAge(of: latestReading, at: currentDate)
        if isStale(latestReading, at: currentDate) {
            return .unknown(reason: staleReadingReason(readingAgeSeconds: readingAgeSeconds))
        }
        if readingAgeSeconds >= agingThresholdSeconds {
            return .aging(latestReading)
        }
        return .current(latestReading)
    }

    static func isStale(_ glucoseReading: GlucoseReading, at currentDate: Date) -> Bool {
        readingAge(of: glucoseReading, at: currentDate) > staleThresholdSeconds
    }

    /// Age in seconds, never negative (a reading timestamped slightly ahead of the local clock counts as brand new).
    static func readingAge(of glucoseReading: GlucoseReading, at currentDate: Date) -> TimeInterval {
        max(currentDate.timeIntervalSince(glucoseReading.readingTimestamp), 0)
    }

    static func staleReadingReason(readingAgeSeconds: TimeInterval) -> String {
        let readingAgeMinutes = Int(readingAgeSeconds / 60)
        return TidebarDiagnosticCode.readingStale.appended(to: "No recent reading. The last one was \(readingAgeMinutes) min ago.")
    }
}
