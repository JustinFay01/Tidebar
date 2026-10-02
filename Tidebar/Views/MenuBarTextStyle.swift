//
//  MenuBarTextStyle.swift
//  Tidebar
//

import SwiftUI

/// System font designs offered for the status item. Raw values are persisted in UserDefaults.
nonisolated enum MenuBarFontDesign: String, CaseIterable, Identifiable, Sendable {
    case standard
    case rounded
    case monospaced
    case serif

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "System"
        case .rounded: "Rounded"
        case .monospaced: "Monospaced"
        case .serif: "Serif"
        }
    }

    var fontDesign: Font.Design {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .monospaced: .monospaced
        case .serif: .serif
        }
    }
}

/// Font weights offered for the status item. Raw values are persisted in UserDefaults.
nonisolated enum MenuBarFontWeight: String, CaseIterable, Identifiable, Sendable {
    case regular
    case medium
    case semibold
    case bold
    case heavy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regular: "Regular"
        case .medium: "Medium"
        case .semibold: "Semibold"
        case .bold: "Bold"
        case .heavy: "Heavy"
        }
    }

    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }
}

/// How the status item's text is drawn.
nonisolated struct MenuBarTextStyle: Equatable, Sendable {
    static let defaultFontSizePoints = 13.0
    /// Larger sizes no longer fit the menu bar's height.
    static let fontSizePointsRange = 10.0...16.0
    static let defaultFontWeight = MenuBarFontWeight.medium
    static let defaultFontDesign = MenuBarFontDesign.standard

    static let defaultStyle = MenuBarTextStyle(
        fontSizePoints: defaultFontSizePoints,
        fontWeight: defaultFontWeight,
        fontDesign: defaultFontDesign
    )

    let fontSizePoints: Double
    let fontWeight: MenuBarFontWeight
    let fontDesign: MenuBarFontDesign

    init(fontSizePoints: Double, fontWeight: MenuBarFontWeight, fontDesign: MenuBarFontDesign) {
        self.fontSizePoints = Self.clampFontSizePoints(fontSizePoints)
        self.fontWeight = fontWeight
        self.fontDesign = fontDesign
    }

    /// Stored values can be edited outside the app (e.g. `defaults write`), so keep them in range.
    static func clampFontSizePoints(_ requestedFontSizePoints: Double) -> Double {
        min(max(requestedFontSizePoints, fontSizePointsRange.lowerBound), fontSizePointsRange.upperBound)
    }

    var font: Font {
        .system(size: fontSizePoints, weight: fontWeight.fontWeight, design: fontDesign.fontDesign).monospacedDigit()
    }

    /// Scales spacing tuned at the default size so layout stays proportional at other sizes.
    func scaledSpacing(_ spacingAtDefaultSize: Double) -> Double {
        spacingAtDefaultSize * fontSizePoints / Self.defaultFontSizePoints
    }
}
