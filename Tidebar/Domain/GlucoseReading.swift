//
//  GlucoseReading.swift
//  Tidebar
//

import Foundation

/// A single provider-agnostic glucose reading. Values are always stored in mg/dL;
/// conversion to other units happens only at display time.
nonisolated struct GlucoseReading: Equatable, Sendable {
    let valueMgPerDeciliter: Int
    let trendDirection: TrendDirection
    let readingTimestamp: Date
}
