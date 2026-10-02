//
//  GlucoseUnit.swift
//  Tidebar
//

import Foundation

/// Unit used to display glucose values. Readings are stored in mg/dL and converted only for display.
nonisolated enum GlucoseUnit: String, CaseIterable, Identifiable, Sendable {
    case milligramsPerDeciliter
    case millimolesPerLiter

    static let milligramsPerDeciliterPerMillimolePerLiter = 18.0182

    var id: String { rawValue }

    var unitLabel: String {
        switch self {
        case .milligramsPerDeciliter: "mg/dL"
        case .millimolesPerLiter: "mmol/L"
        }
    }

    /// Widest typical value in this unit, used to reserve a stable width in the menu bar.
    var widestTypicalValuePlaceholder: String {
        switch self {
        case .milligramsPerDeciliter: "000"
        case .millimolesPerLiter: "00.0"
        }
    }

    static func convertToMillimolesPerLiter(valueMgPerDeciliter: Int) -> Double {
        Double(valueMgPerDeciliter) / milligramsPerDeciliterPerMillimolePerLiter
    }

    /// Formats a mg/dL value in this unit, respecting the locale's decimal separator.
    func formattedValue(fromMgPerDeciliter valueMgPerDeciliter: Int, locale: Locale = .autoupdatingCurrent) -> String {
        switch self {
        case .milligramsPerDeciliter:
            return valueMgPerDeciliter.formatted(.number.grouping(.never).locale(locale))
        case .millimolesPerLiter:
            let valueMillimolesPerLiter = Self.convertToMillimolesPerLiter(valueMgPerDeciliter: valueMgPerDeciliter)
            return valueMillimolesPerLiter.formatted(
                .number.precision(.fractionLength(1)).grouping(.never).locale(locale)
            )
        }
    }
}
