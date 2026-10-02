//
//  MenuBarTextStyleTests.swift
//  TidebarTests
//

import Foundation
import Testing
@testable import Tidebar

struct MenuBarTextStyleTests {
    @Test(arguments: [(4.0, 10.0), (10.0, 10.0), (13.0, 13.0), (16.0, 16.0), (40.0, 16.0)])
    func clampsFontSizeToMenuBarRange(requestedFontSizePoints: Double, expectedFontSizePoints: Double) {
        let textStyle = MenuBarTextStyle(fontSizePoints: requestedFontSizePoints, fontWeight: .regular, fontDesign: .standard)
        #expect(textStyle.fontSizePoints == expectedFontSizePoints)
    }

    @Test(arguments: [(13.0, 3.0), (10.0, 3.0 * 10 / 13), (16.0, 3.0 * 16 / 13)])
    func scalesSpacingWithFontSize(fontSizePoints: Double, expectedSpacing: Double) {
        let textStyle = MenuBarTextStyle(fontSizePoints: fontSizePoints, fontWeight: .medium, fontDesign: .standard)
        #expect(abs(textStyle.scaledSpacing(3) - expectedSpacing) < 0.000_1)
    }

    @Test func defaultStyleMatchesDefaults() {
        #expect(MenuBarTextStyle.defaultStyle.fontSizePoints == 13)
        #expect(MenuBarTextStyle.defaultStyle.fontWeight == .medium)
        #expect(MenuBarTextStyle.defaultStyle.fontDesign == .standard)
    }

    @Test(arguments: MenuBarFontWeight.allCases)
    func fontWeightRoundTripsThroughStoredRawValue(fontWeight: MenuBarFontWeight) {
        #expect(MenuBarFontWeight(rawValue: fontWeight.rawValue) == fontWeight)
    }

    @Test(arguments: MenuBarFontDesign.allCases)
    func fontDesignRoundTripsThroughStoredRawValue(fontDesign: MenuBarFontDesign) {
        #expect(MenuBarFontDesign(rawValue: fontDesign.rawValue) == fontDesign)
    }
}
