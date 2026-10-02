//
//  GlucoseUnitTests.swift
//  TidebarTests
//

import Foundation
import Testing
@testable import Tidebar

struct GlucoseUnitTests {
    @Test(arguments: [
        (18, 0.999),
        (100, 5.550),
        (180, 9.990),
        (400, 22.200),
    ])
    func convertsMgPerDeciliterToMillimolesPerLiter(valueMgPerDeciliter: Int, expectedMillimolesPerLiter: Double) {
        let convertedValue = GlucoseUnit.convertToMillimolesPerLiter(valueMgPerDeciliter: valueMgPerDeciliter)
        #expect(abs(convertedValue - expectedMillimolesPerLiter) < 0.001)
    }

    @Test(arguments: [
        (GlucoseUnit.milligramsPerDeciliter, 112, "en_US", "112"),
        (GlucoseUnit.milligramsPerDeciliter, 40, "de_DE", "40"),
        (GlucoseUnit.milligramsPerDeciliter, 1_200, "en_US", "1200"),
        (GlucoseUnit.millimolesPerLiter, 112, "en_US", "6.2"),
        (GlucoseUnit.millimolesPerLiter, 112, "de_DE", "6,2"),
        (GlucoseUnit.millimolesPerLiter, 90, "en_GB", "5.0"),
        (GlucoseUnit.millimolesPerLiter, 400, "fr_FR", "22,2"),
    ])
    func formatsValuesForLocale(
        glucoseUnit: GlucoseUnit,
        valueMgPerDeciliter: Int,
        localeIdentifier: String,
        expectedFormattedValue: String
    ) {
        let formattedValue = glucoseUnit.formattedValue(
            fromMgPerDeciliter: valueMgPerDeciliter,
            locale: Locale(identifier: localeIdentifier)
        )
        #expect(formattedValue == expectedFormattedValue)
    }
}
