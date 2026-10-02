//
//  TrendDirection.swift
//  Tidebar
//

import Foundation

/// Direction and rate of glucose change. Raw values match the strings returned by the Dexcom Share API.
nonisolated enum TrendDirection: String, CaseIterable, Sendable {
    case doubleUp = "DoubleUp"
    case singleUp = "SingleUp"
    case fortyFiveUp = "FortyFiveUp"
    case flat = "Flat"
    case fortyFiveDown = "FortyFiveDown"
    case singleDown = "SingleDown"
    case doubleDown = "DoubleDown"
    case notComputable = "NotComputable"
    case rateOutOfRange = "RateOutOfRange"
    case none = "None"

    /// Arrow shown next to the glucose value, or `nil` when the trend cannot be determined.
    var arrowSymbol: String? {
        switch self {
        case .doubleUp: "⇈"
        case .singleUp: "↑"
        case .fortyFiveUp: "↗"
        case .flat: "→"
        case .fortyFiveDown: "↘"
        case .singleDown: "↓"
        case .doubleDown: "⇊"
        case .notComputable, .rateOutOfRange, .none: nil
        }
    }

    var hasDeterminableDirection: Bool {
        arrowSymbol != nil
    }

    /// Human-readable description, e.g. for accessibility and the dropdown menu.
    var trendDescription: String {
        switch self {
        case .doubleUp: "Rising quickly"
        case .singleUp: "Rising"
        case .fortyFiveUp: "Rising slightly"
        case .flat: "Steady"
        case .fortyFiveDown: "Falling slightly"
        case .singleDown: "Falling"
        case .doubleDown: "Falling quickly"
        case .notComputable: "Unable to determine trend"
        case .rateOutOfRange: "Trend unavailable"
        case .none: "No trend"
        }
    }
}
