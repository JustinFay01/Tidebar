//
//  GlucoseStatusFormatter.swift
//  Tidebar
//

import Foundation

/// Turns display state into text. All unit conversion and formatting happens here, at display time.
nonisolated enum GlucoseStatusFormatter {
    static let unknownValueText = "---"
    static let indeterminateTrendSymbol = "?"
    static let indeterminateTrendSymbolName = "questionmark"

    /// What the status item shows, split into parts so the label can draw trend arrows as SF Symbols.
    struct MenuBarStatusContent: Equatable, Sendable {
        let valueText: String
        let trendSymbolNames: [String]
        let ageSuffixText: String?
        let isDimmed: Bool
    }

    /// `112 →` when current, `112 → 8m` dimmed when aging, `--- ?` when unknown.
    static func menuBarStatusContent(
        for displayState: GlucoseDisplayState,
        glucoseUnit: GlucoseUnit,
        currentDate: Date,
        locale: Locale = .autoupdatingCurrent
    ) -> MenuBarStatusContent {
        switch displayState {
        case .unknown:
            return MenuBarStatusContent(
                valueText: unknownValueText,
                trendSymbolNames: [indeterminateTrendSymbolName],
                ageSuffixText: nil,
                isDimmed: false
            )
        case .current(let glucoseReading):
            return MenuBarStatusContent(
                valueText: glucoseUnit.formattedValue(fromMgPerDeciliter: glucoseReading.valueMgPerDeciliter, locale: locale),
                trendSymbolNames: trendSymbolNames(for: glucoseReading.trendDirection),
                ageSuffixText: nil,
                isDimmed: false
            )
        case .aging(let glucoseReading):
            return MenuBarStatusContent(
                valueText: glucoseUnit.formattedValue(fromMgPerDeciliter: glucoseReading.valueMgPerDeciliter, locale: locale),
                trendSymbolNames: trendSymbolNames(for: glucoseReading.trendDirection),
                ageSuffixText: compactAge(of: glucoseReading, currentDate: currentDate),
                isDimmed: true
            )
        }
    }

    /// SF Symbol names for the trend. There is no double-arrow symbol before macOS 15,
    /// so double trends repeat the single arrow.
    static func trendSymbolNames(for trendDirection: TrendDirection) -> [String] {
        switch trendDirection {
        case .doubleUp: ["arrow.up", "arrow.up"]
        case .singleUp: ["arrow.up"]
        case .fortyFiveUp: ["arrow.up.right"]
        case .flat: ["arrow.right"]
        case .fortyFiveDown: ["arrow.down.right"]
        case .singleDown: ["arrow.down"]
        case .doubleDown: ["arrow.down", "arrow.down"]
        case .notComputable, .rateOutOfRange, .none: [indeterminateTrendSymbolName]
        }
    }

    /// Typical content laid out invisibly behind the real content to keep the menu bar width stable:
    /// the widest value with each single-arrow symbol, since symbol widths vary by font.
    /// Double arrows are rare and deliberately not reserved, so normal readings carry no extra padding.
    static func widthReservingContents(for glucoseUnit: GlucoseUnit) -> [MenuBarStatusContent] {
        singleTrendSymbolNames.map { trendSymbolName in
            MenuBarStatusContent(
                valueText: glucoseUnit.widestTypicalValuePlaceholder,
                trendSymbolNames: [trendSymbolName],
                ageSuffixText: nil,
                isDimmed: false
            )
        }
    }

    /// Every distinct symbol shown alone, i.e. all trends except the doubled arrows.
    static var singleTrendSymbolNames: [String] {
        var uniqueSymbolNames: [String] = []
        for trendDirection in TrendDirection.allCases {
            let symbolNames = trendSymbolNames(for: trendDirection)
            if symbolNames.count == 1, let symbolName = symbolNames.first, !uniqueSymbolNames.contains(symbolName) {
                uniqueSymbolNames.append(symbolName)
            }
        }
        return uniqueSymbolNames
    }

    /// Unicode arrow used in plain-text contexts such as the dropdown menu.
    static func trendSymbol(for trendDirection: TrendDirection) -> String {
        trendDirection.arrowSymbol ?? indeterminateTrendSymbol
    }

    /// e.g. `8m`
    static func compactAge(of glucoseReading: GlucoseReading, currentDate: Date) -> String {
        "\(wholeMinutesOld(glucoseReading, currentDate: currentDate))m"
    }

    /// e.g. `Just now`, `3 min ago`, `1 hr 5 min ago`
    static func relativeAgeDescription(of glucoseReading: GlucoseReading, currentDate: Date) -> String {
        let readingAgeMinutes = wholeMinutesOld(glucoseReading, currentDate: currentDate)
        if readingAgeMinutes < 1 {
            return "Just now"
        }
        if readingAgeMinutes < 60 {
            return "\(readingAgeMinutes) min ago"
        }
        let readingAgeHours = readingAgeMinutes / 60
        let remainingMinutes = readingAgeMinutes % 60
        return remainingMinutes == 0
            ? "\(readingAgeHours) hr ago"
            : "\(readingAgeHours) hr \(remainingMinutes) min ago"
    }

    /// Spoken description for VoiceOver, e.g. "112 milligrams per deciliter, steady".
    static func accessibilityDescription(
        for displayState: GlucoseDisplayState,
        glucoseUnit: GlucoseUnit,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        switch displayState {
        case .unknown(let reason):
            return "Glucose unknown. \(reason)"
        case .current(let glucoseReading), .aging(let glucoseReading):
            let formattedValue = glucoseUnit.formattedValue(fromMgPerDeciliter: glucoseReading.valueMgPerDeciliter, locale: locale)
            return "Glucose \(formattedValue) \(glucoseUnit.unitLabel), \(glucoseReading.trendDirection.trendDescription)"
        }
    }

    private static func wholeMinutesOld(_ glucoseReading: GlucoseReading, currentDate: Date) -> Int {
        Int(GlucoseReadingFreshness.readingAge(of: glucoseReading, at: currentDate) / 60)
    }
}
