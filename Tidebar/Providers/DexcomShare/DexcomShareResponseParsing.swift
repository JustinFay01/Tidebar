//
//  DexcomShareResponseParsing.swift
//  Tidebar
//

import Foundation

/// Parses Dexcom `Date(1690000000000)` timestamps (epoch milliseconds, optionally followed by a
/// `+hhmm`/`-hhmm` offset, which does not affect the instant) into `Date`.
nonisolated enum DexcomShareTimestampParser {
    static func parseDate(fromDexcomTimestamp dexcomTimestamp: String) -> Date? {
        let timestampPattern = /^Date\((?<epochMilliseconds>-?\d+)(?<timeZoneOffset>[+-]\d{4})?\)$/
        guard let timestampMatch = dexcomTimestamp.wholeMatch(of: timestampPattern),
              let epochMilliseconds = Int64(timestampMatch.output.epochMilliseconds)
        else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(epochMilliseconds) / 1000)
    }
}

/// One entry of the `ReadPublisherLatestGlucoseValues` response.
nonisolated struct DexcomShareGlucoseEntry: Decodable, Sendable {
    let wallTimeTimestamp: String
    let valueMgPerDeciliter: Int
    let trendString: String

    private enum CodingKeys: String, CodingKey {
        case wallTimeTimestamp = "WT"
        case valueMgPerDeciliter = "Value"
        case trendString = "Trend"
    }

    /// Legacy Share responses used integer trends, ordered as in pydexcom's `DEXCOM_TREND_DIRECTIONS`.
    private static let legacyTrendStringsByIndex = [
        "None", "DoubleUp", "SingleUp", "FortyFiveUp", "Flat",
        "FortyFiveDown", "SingleDown", "DoubleDown", "NotComputable", "RateOutOfRange",
    ]

    init(from decoder: Decoder) throws {
        let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
        wallTimeTimestamp = try keyedContainer.decode(String.self, forKey: .wallTimeTimestamp)
        valueMgPerDeciliter = try keyedContainer.decode(Int.self, forKey: .valueMgPerDeciliter)
        trendString = try Self.decodeTrendString(from: keyedContainer)
    }

    private static func decodeTrendString(from keyedContainer: KeyedDecodingContainer<CodingKeys>) throws -> String {
        if let trendString = try? keyedContainer.decode(String.self, forKey: .trendString) {
            return trendString
        }
        let legacyTrendIndex = try keyedContainer.decode(Int.self, forKey: .trendString)
        return legacyTrendStringsByIndex.indices.contains(legacyTrendIndex)
            ? legacyTrendStringsByIndex[legacyTrendIndex]
            : TrendDirection.none.rawValue
    }
}

/// Failures reported by the Share API in its `{"Code": …, "Message": …}` error body.
nonisolated enum DexcomShareServerFailure: Equatable, Sendable {
    case sessionExpiredOrInvalid
    case invalidCredentials
    case maximumAuthenticationAttemptsExceeded
    case unrecognized(code: String?)
}

nonisolated enum DexcomShareResponseParsing {
    /// Session and account identifiers equal to this UUID indicate failed authentication.
    static let defaultIdentifier = "00000000-0000-0000-0000-000000000000"

    static func parseGlucoseReadings(fromResponseData responseData: Data) throws -> [GlucoseReading] {
        let glucoseEntries: [DexcomShareGlucoseEntry]
        do {
            glucoseEntries = try JSONDecoder().decode([DexcomShareGlucoseEntry].self, from: responseData)
        } catch {
            throw GlucoseProviderError.unexpectedResponse(description: "Glucose readings were not in the expected format.")
        }
        let glucoseReadings = try glucoseEntries.map(makeGlucoseReading(from:))
        return glucoseReadings.sorted { firstReading, secondReading in
            firstReading.readingTimestamp > secondReading.readingTimestamp
        }
    }

    static func makeGlucoseReading(from glucoseEntry: DexcomShareGlucoseEntry) throws -> GlucoseReading {
        guard let readingTimestamp = DexcomShareTimestampParser.parseDate(fromDexcomTimestamp: glucoseEntry.wallTimeTimestamp) else {
            throw GlucoseProviderError.unexpectedResponse(description: "A glucose reading had an unreadable timestamp.")
        }
        return GlucoseReading(
            valueMgPerDeciliter: glucoseEntry.valueMgPerDeciliter,
            trendDirection: mapTrendDirection(fromTrendString: glucoseEntry.trendString),
            readingTimestamp: readingTimestamp
        )
    }

    /// Unrecognized trend strings are shown as "no trend" rather than failing the whole reading.
    static func mapTrendDirection(fromTrendString trendString: String) -> TrendDirection {
        TrendDirection(rawValue: trendString) ?? .none
    }

    /// Account and session endpoints return a bare JSON string containing a UUID.
    /// Returns `nil` for the all-zero UUID, which Dexcom returns for failed authentication.
    static func parseIdentifier(fromResponseData responseData: Data) throws -> String? {
        guard let identifierString = try? JSONDecoder().decode(String.self, from: responseData),
              UUID(uuidString: identifierString) != nil
        else {
            throw GlucoseProviderError.unexpectedResponse(description: "Sign-in response was not in the expected format.")
        }
        return identifierString == defaultIdentifier ? nil : identifierString
    }

    static func parseServerFailure(fromResponseData responseData: Data) -> DexcomShareServerFailure {
        let errorBody = try? JSONDecoder().decode(DexcomShareErrorBody.self, from: responseData)
        return classifyServerFailure(code: errorBody?.code, message: errorBody?.message)
    }

    /// Mirrors pydexcom's `_handle_error_code`.
    static func classifyServerFailure(code: String?, message: String?) -> DexcomShareServerFailure {
        let messageText = message ?? ""
        switch code {
        case "SessionIdNotFound", "SessionNotValid":
            return .sessionExpiredOrInvalid
        case "AccountPasswordInvalid":
            return .invalidCredentials
        case "SSO_AuthenticateMaxAttemptsExceeded":
            return .maximumAuthenticationAttemptsExceeded
        case "SSO_InternalError"
            where messageText.contains("Cannot Authenticate by AccountName")
                || messageText.contains("Cannot Authenticate by AccountId"):
            return .invalidCredentials
        case "InvalidArgument" where messageText.contains("accountName") || messageText.contains("password"):
            return .invalidCredentials
        default:
            return .unrecognized(code: code)
        }
    }
}

private nonisolated struct DexcomShareErrorBody: Decodable {
    let code: String?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case code = "Code"
        case message = "Message"
    }
}
