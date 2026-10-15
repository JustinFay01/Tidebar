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
        let differenceContent: DifferenceContent?
        let ageSuffixText: String?
        let isDimmed: Bool
    }

    /// The change since the previous reading: the sign drawn as an SF Symbol, then the unsigned amount.
    struct DifferenceContent: Equatable, Sendable {
        let signSymbolName: String
        let magnitudeText: String
    }

    /// `112 → ⊕4` when current, `112 → ⊕4 8m` dimmed when aging, `--- ?` when unknown.
    /// The change is left out until there is a previous reading to compare against.
    /// - Parameter showsDifference: the user's setting for showing the change in the menu bar.
    /// - Parameter dimsAgingReadings: the user's setting for dimming aging readings; the age suffix shows either way.
    static func menuBarStatusContent(
        for displayState: GlucoseDisplayState,
        glucoseUnit: GlucoseUnit,
        currentDate: Date,
        showsDifference: Bool,
        dimsAgingReadings: Bool,
        locale: Locale = .autoupdatingCurrent
    ) -> MenuBarStatusContent {
        switch displayState {
        case .unknown:
            return MenuBarStatusContent(
                valueText: unknownValueText,
                trendSymbolNames: [indeterminateTrendSymbolName],
                differenceContent: nil,
                ageSuffixText: nil,
                isDimmed: false
            )
        case .current(let readings):
            return MenuBarStatusContent(
                valueText: glucoseUnit.formattedValue(fromMgPerDeciliter: readings.currentReading.valueMgPerDeciliter, locale: locale),
                trendSymbolNames: trendSymbolNames(for: readings.currentReading.trendDirection),
                differenceContent: showsDifference ? differenceContent(for: readings, glucoseUnit: glucoseUnit, locale: locale) : nil,
                ageSuffixText: nil,
                isDimmed: false
            )
        case .aging(let readings):
            return MenuBarStatusContent(
                valueText: glucoseUnit.formattedValue(fromMgPerDeciliter: readings.currentReading.valueMgPerDeciliter, locale: locale),
                trendSymbolNames: trendSymbolNames(for: readings.currentReading.trendDirection),
                differenceContent: showsDifference ? differenceContent(for: readings, glucoseUnit: glucoseUnit, locale: locale) : nil,
                ageSuffixText: compactAge(of: readings.currentReading, currentDate: currentDate),
                isDimmed: dimsAgingReadings
            )
        }
    }

    /// `nil` when there is no previous reading to compare against.
    static func differenceContent(
        for readings: DisplayedReadings,
        glucoseUnit: GlucoseUnit,
        locale: Locale = .autoupdatingCurrent
    ) -> DifferenceContent? {
        guard let differenceMgPerDeciliter = readings.differenceMgPerDeciliter else {
            return nil
        }
        return DifferenceContent(
            signSymbolName: differenceSignSymbolName(for: differenceMgPerDeciliter),
            magnitudeText: glucoseUnit.formattedValue(fromMgPerDeciliter: abs(differenceMgPerDeciliter), locale: locale)
        )
    }

    static func differenceSignSymbolName(for differenceMgPerDeciliter: Int) -> String {
        if differenceMgPerDeciliter > 0 {
            return "plus"
        }
        if differenceMgPerDeciliter < 0 {
            return "minus"
        }
        return "plusminus"
    }

    /// e.g. `+4`, `−0.3`, `±0` for plain-text contexts such as the dropdown menu, which draws SF Symbols
    /// in a fixed color instead of its own text color. `nil` when there is no previous reading to compare against.
    static func differencePlainText(
        for readings: DisplayedReadings,
        glucoseUnit: GlucoseUnit,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard let differenceMgPerDeciliter = readings.differenceMgPerDeciliter else {
            return nil
        }
        let magnitudeText = glucoseUnit.formattedValue(fromMgPerDeciliter: abs(differenceMgPerDeciliter), locale: locale)
        return "\(differenceSignCharacter(for: differenceMgPerDeciliter))\(magnitudeText)"
    }

    /// The plain-text counterpart of `differenceSignSymbolName(for:)`, using the true minus sign.
    static func differenceSignCharacter(for differenceMgPerDeciliter: Int) -> String {
        if differenceMgPerDeciliter > 0 {
            return "+"
        }
        if differenceMgPerDeciliter < 0 {
            return "\u{2212}"
        }
        return "\u{00B1}"
    }

    /// e.g. `up 4 since the last reading`, or `nil` when there is no previous reading to compare against.
    static func spokenDifference(for readings: DisplayedReadings, glucoseUnit: GlucoseUnit, locale: Locale) -> String? {
        guard let differenceMgPerDeciliter = readings.differenceMgPerDeciliter else {
            return nil
        }
        guard differenceMgPerDeciliter != 0 else {
            return "no change since the last reading"
        }
        let direction = differenceMgPerDeciliter > 0 ? "up" : "down"
        let magnitudeText = glucoseUnit.formattedValue(fromMgPerDeciliter: abs(differenceMgPerDeciliter), locale: locale)
        return "\(direction) \(magnitudeText) since the last reading"
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
    /// - Parameter isDifferenceShown: also reserves the widest typical change, so the width holds as it changes.
    static func widthReservingContents(for glucoseUnit: GlucoseUnit, isDifferenceShown: Bool) -> [MenuBarStatusContent] {
        singleTrendSymbolNames.map { trendSymbolName in
            MenuBarStatusContent(
                valueText: glucoseUnit.widestTypicalValuePlaceholder,
                trendSymbolNames: [trendSymbolName],
                differenceContent: isDifferenceShown ? widestTypicalDifferenceContent(for: glucoseUnit) : nil,
                ageSuffixText: nil,
                isDimmed: false
            )
        }
    }

    private static func widestTypicalDifferenceContent(for glucoseUnit: GlucoseUnit) -> DifferenceContent {
        DifferenceContent(
            signSymbolName: differenceSignSymbolName(for: 1),
            magnitudeText: glucoseUnit.widestTypicalDifferencePlaceholder
        )
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

    /// Spoken description for VoiceOver, e.g. "112 milligrams per deciliter, steady, up 4 since the last reading".
    /// - Parameter showsDifference: whether the menu bar shows the change, so VoiceOver speaks only what is shown.
    static func accessibilityDescription(
        for displayState: GlucoseDisplayState,
        glucoseUnit: GlucoseUnit,
        showsDifference: Bool,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        switch displayState {
        case .unknown(let reason):
            return "Glucose unknown. \(reason)"
        case .current(let readings), .aging(let readings):
            let glucoseReading = readings.currentReading
            let formattedValue = glucoseUnit.formattedValue(fromMgPerDeciliter: glucoseReading.valueMgPerDeciliter, locale: locale)
            let description = "Glucose \(formattedValue) \(glucoseUnit.unitLabel), \(glucoseReading.trendDirection.trendDescription)"
            guard showsDifference, let spokenDifference = spokenDifference(for: readings, glucoseUnit: glucoseUnit, locale: locale) else {
                return description
            }
            return "\(description), \(spokenDifference)"
        }
    }

    private static func wholeMinutesOld(_ glucoseReading: GlucoseReading, currentDate: Date) -> Int {
        Int(GlucoseReadingFreshness.readingAge(of: glucoseReading, at: currentDate) / 60)
    }
}
