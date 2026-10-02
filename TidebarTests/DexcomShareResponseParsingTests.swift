//
//  DexcomShareResponseParsingTests.swift
//  TidebarTests
//

import Foundation
import Testing
@testable import Tidebar

struct DexcomShareTimestampParserTests {
    @Test(arguments: [
        ("Date(1690000000000)", 1_690_000_000.0),
        ("Date(1690000000123)", 1_690_000_000.123),
        ("Date(1690000000000-0400)", 1_690_000_000.0),
        ("Date(1690000000000+0900)", 1_690_000_000.0),
        ("Date(0)", 0.0),
    ])
    func parsesValidTimestamps(dexcomTimestamp: String, expectedSecondsSince1970: Double) throws {
        let parsedDate = try #require(DexcomShareTimestampParser.parseDate(fromDexcomTimestamp: dexcomTimestamp))
        #expect(abs(parsedDate.timeIntervalSince1970 - expectedSecondsSince1970) < 0.000_1)
    }

    @Test(arguments: [
        "",
        "1690000000000",
        "Date()",
        "Date(abc)",
        "Date(1690000000000",
        "Date(1690000000000-04)",
        " Date(1690000000000)",
        "/Date(1690000000000)/",
    ])
    func rejectsMalformedTimestamps(dexcomTimestamp: String) {
        #expect(DexcomShareTimestampParser.parseDate(fromDexcomTimestamp: dexcomTimestamp) == nil)
    }
}

struct DexcomShareResponseParsingTests {
    @Test func parsesFixtureReadingsNewestFirst() throws {
        let responseData = try TestFixtures.loadFixtureData(named: "share-glucose-readings")

        let glucoseReadings = try DexcomShareResponseParsing.parseGlucoseReadings(fromResponseData: responseData)

        #expect(glucoseReadings.count == 3)
        let newestReading = try #require(glucoseReadings.first)
        #expect(newestReading.valueMgPerDeciliter == 112)
        #expect(newestReading.trendDirection == .flat)
        #expect(newestReading.readingTimestamp == Date(timeIntervalSince1970: 1_690_000_600))
        #expect(glucoseReadings.map(\.valueMgPerDeciliter) == [112, 108, 101])
    }

    @Test func parsesEmptyResponseAsNoReadings() throws {
        let responseData = try TestFixtures.loadFixtureData(named: "share-glucose-readings-empty")
        #expect(try DexcomShareResponseParsing.parseGlucoseReadings(fromResponseData: responseData).isEmpty)
    }

    @Test(arguments: TrendDirection.allCases)
    func mapsEveryTrendString(expectedTrendDirection: TrendDirection) throws {
        let responseData = Data("""
            [{"WT":"Date(1690000000000)","Value":150,"Trend":"\(expectedTrendDirection.rawValue)"}]
            """.utf8)

        let glucoseReadings = try DexcomShareResponseParsing.parseGlucoseReadings(fromResponseData: responseData)

        #expect(glucoseReadings.first?.trendDirection == expectedTrendDirection)
    }

    @Test(arguments: [
        (4, TrendDirection.flat),
        (1, TrendDirection.doubleUp),
        (7, TrendDirection.doubleDown),
        (9, TrendDirection.rateOutOfRange),
        (42, TrendDirection.none),
    ])
    func mapsLegacyIntegerTrends(legacyTrendIndex: Int, expectedTrendDirection: TrendDirection) throws {
        let responseData = Data("""
            [{"WT":"Date(1690000000000)","Value":150,"Trend":\(legacyTrendIndex)}]
            """.utf8)

        let glucoseReadings = try DexcomShareResponseParsing.parseGlucoseReadings(fromResponseData: responseData)

        #expect(glucoseReadings.first?.trendDirection == expectedTrendDirection)
    }

    @Test func mapsUnknownTrendStringToNone() {
        #expect(DexcomShareResponseParsing.mapTrendDirection(fromTrendString: "Sideways") == .none)
    }

    @Test(arguments: [
        #"{"not":"an array"}"#,
        #"[{"WT":"Date(1690000000000)","Trend":"Flat"}]"#,
        #"[{"WT":"yesterday","Value":100,"Trend":"Flat"}]"#,
        "",
    ])
    func rejectsMalformedReadings(responseBody: String) {
        #expect(throws: GlucoseProviderError.self) {
            try DexcomShareResponseParsing.parseGlucoseReadings(fromResponseData: Data(responseBody.utf8))
        }
    }

    @Test func parsesIdentifierAndTreatsAllZeroUUIDAsMissing() throws {
        let validIdentifier = "1e913fce-5a34-4d27-a991-b6cb3a3bd3d8"
        #expect(try DexcomShareResponseParsing.parseIdentifier(fromResponseData: Data("\"\(validIdentifier)\"".utf8)) == validIdentifier)
        #expect(try DexcomShareResponseParsing.parseIdentifier(
            fromResponseData: Data("\"\(DexcomShareResponseParsing.defaultIdentifier)\"".utf8)
        ) == nil)
        #expect(throws: GlucoseProviderError.self) {
            try DexcomShareResponseParsing.parseIdentifier(fromResponseData: Data("\"not-a-uuid\"".utf8))
        }
    }

    @Test(arguments: [
        ("share-error-session-not-valid", DexcomShareServerFailure.sessionExpiredOrInvalid),
        ("share-error-password-invalid", DexcomShareServerFailure.invalidCredentials),
        ("share-error-max-attempts", DexcomShareServerFailure.maximumAuthenticationAttemptsExceeded),
    ])
    func classifiesFixtureErrorBodies(fixtureName: String, expectedServerFailure: DexcomShareServerFailure) throws {
        let responseData = try TestFixtures.loadFixtureData(named: fixtureName)
        #expect(DexcomShareResponseParsing.parseServerFailure(fromResponseData: responseData) == expectedServerFailure)
    }

    @Test(arguments: [
        ("SessionIdNotFound", nil, DexcomShareServerFailure.sessionExpiredOrInvalid),
        ("SSO_InternalError", "Cannot Authenticate by AccountName", DexcomShareServerFailure.invalidCredentials),
        ("SSO_InternalError", "Something else", DexcomShareServerFailure.unrecognized(code: "SSO_InternalError")),
        ("InvalidArgument", "accountName must not be empty", DexcomShareServerFailure.invalidCredentials),
        (nil, nil, DexcomShareServerFailure.unrecognized(code: nil)),
    ] as [(String?, String?, DexcomShareServerFailure)])
    func classifiesErrorCodes(code: String?, message: String?, expectedServerFailure: DexcomShareServerFailure) {
        #expect(DexcomShareResponseParsing.classifyServerFailure(code: code, message: message) == expectedServerFailure)
    }
}
