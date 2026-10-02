//
//  DexcomShareGlucoseProviderTests.swift
//  TidebarTests
//

import Foundation
import Testing
@testable import Tidebar

struct DexcomShareGlucoseProviderTests {
    static let accountIdentifier = "1e913fce-5a34-4d27-a991-b6cb3a3bd3d8"
    static let firstSessionIdentifier = "9a1c4b52-11d8-4f0e-8a51-0c1f2b0f1e01"
    static let secondSessionIdentifier = "9a1c4b52-11d8-4f0e-8a51-0c1f2b0f1e02"

    let stubHTTPClient = StubHTTPClient()
    let testClock = MutableTestClock()

    func makeProvider(region: DexcomShareRegion = .unitedStates) -> DexcomShareGlucoseProvider {
        DexcomShareGlucoseProvider(
            username: "share-user",
            password: "share-password",
            region: region,
            httpClient: stubHTTPClient,
            currentDateProvider: testClock.makeDateProvider()
        )
    }

    func enqueueSuccessfulLogin(sessionIdentifier: String = firstSessionIdentifier) async {
        stubHTTPClient.enqueueResponse(for: .authenticatePublisherAccount, responseBody: "\"\(Self.accountIdentifier)\"")
        stubHTTPClient.enqueueResponse(for: .loginPublisherAccountById, responseBody: "\"\(sessionIdentifier)\"")
    }

    func enqueueFixtureReadings() async throws {
        let fixtureData = try TestFixtures.loadFixtureData(named: "share-glucose-readings")
        stubHTTPClient.enqueueResponse(for: .readPublisherLatestGlucoseValues, responseData: fixtureData)
    }

    func enqueueFixtureError(named fixtureName: String, for endpoint: DexcomShareEndpoint) async throws {
        let fixtureData = try TestFixtures.loadFixtureData(named: fixtureName)
        stubHTTPClient.enqueueResponse(for: endpoint, statusCode: 500, responseData: fixtureData)
    }

    static func decodeJSONBody(of urlRequest: URLRequest) throws -> [String: String] {
        let requestBody = try #require(urlRequest.httpBody)
        return try JSONDecoder().decode([String: String].self, from: requestBody)
    }

    static func queryValue(named queryItemName: String, in urlRequest: URLRequest) -> String? {
        guard let requestURL = urlRequest.url,
              let urlComponents = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        return urlComponents.queryItems?.first { $0.name == queryItemName }?.value
    }

    // MARK: - Happy path

    @Test func logsInThenFetchesLatestReading() async throws {
        await enqueueSuccessfulLogin()
        try await enqueueFixtureReadings()

        let latestReading = try await makeProvider().fetchLatestReading()

        #expect(latestReading.valueMgPerDeciliter == 112)
        #expect(latestReading.trendDirection == .flat)
        #expect(stubHTTPClient.recordedEndpoints() == [
            .authenticatePublisherAccount, .loginPublisherAccountById, .readPublisherLatestGlucoseValues,
        ])

        let recordedRequests = stubHTTPClient.recordedRequests
        let authenticateBody = try Self.decodeJSONBody(of: recordedRequests[0])
        #expect(authenticateBody["accountName"] == "share-user")
        #expect(authenticateBody["password"] == "share-password")
        #expect(authenticateBody["applicationId"] == DexcomShareRegion.unitedStates.applicationIdentifier)

        let loginBody = try Self.decodeJSONBody(of: recordedRequests[1])
        #expect(loginBody["accountId"] == Self.accountIdentifier)

        let readingsRequest = recordedRequests[2]
        #expect(readingsRequest.httpMethod == "POST")
        #expect(Self.queryValue(named: "sessionId", in: readingsRequest) == Self.firstSessionIdentifier)
        #expect(Self.queryValue(named: "minutes", in: readingsRequest) == "1440")
        #expect(Self.queryValue(named: "maxCount", in: readingsRequest) == "1")
    }

    @Test(arguments: DexcomShareRegion.allCases)
    func usesRegionBaseURL(region: DexcomShareRegion) async throws {
        await enqueueSuccessfulLogin()
        try await enqueueFixtureReadings()

        _ = try await makeProvider(region: region).fetchLatestReading()

        let firstRequestURL = try #require(stubHTTPClient.recordedRequests.first?.url)
        #expect(firstRequestURL.absoluteString.hasPrefix(region.baseURLString))
    }

    @Test func reusesCachedSessionAcrossFetches() async throws {
        await enqueueSuccessfulLogin()
        try await enqueueFixtureReadings()
        try await enqueueFixtureReadings()
        let provider = makeProvider()

        _ = try await provider.fetchLatestReading()
        _ = try await provider.fetchLatestReading()

        #expect(stubHTTPClient.recordedEndpoints() == [
            .authenticatePublisherAccount, .loginPublisherAccountById,
            .readPublisherLatestGlucoseValues, .readPublisherLatestGlucoseValues,
        ])
    }

    @Test func requestsRecentReadingsWithClampedLookback() async throws {
        await enqueueSuccessfulLogin()
        try await enqueueFixtureReadings()

        let recentReadings = try await makeProvider().fetchRecentReadings(withinMinutes: 60)

        #expect(recentReadings.count == 3)
        let readingsRequest = try #require(stubHTTPClient.recordedRequests.last)
        #expect(Self.queryValue(named: "minutes", in: readingsRequest) == "60")
        #expect(Self.queryValue(named: "maxCount", in: readingsRequest) == "13")
    }

    @Test(arguments: [(-5, 1), (0, 1), (60, 60), (5_000, 1440)])
    func clampsLookbackMinutes(requestedMinutes: Int, expectedMinutes: Int) {
        #expect(DexcomShareGlucoseProvider.clampLookbackMinutes(requestedMinutes) == expectedMinutes)
    }

    // MARK: - Session expiry

    @Test func sessionExpiredLogsInAgainOnceAndRetries() async throws {
        await enqueueSuccessfulLogin(sessionIdentifier: Self.firstSessionIdentifier)
        try await enqueueFixtureError(named: "share-error-session-not-valid", for: .readPublisherLatestGlucoseValues)
        stubHTTPClient.enqueueResponse(for: .loginPublisherAccountById, responseBody: "\"\(Self.secondSessionIdentifier)\"")
        try await enqueueFixtureReadings()

        let latestReading = try await makeProvider().fetchLatestReading()

        #expect(latestReading.valueMgPerDeciliter == 112)
        #expect(stubHTTPClient.recordedEndpoints() == [
            .authenticatePublisherAccount, .loginPublisherAccountById, .readPublisherLatestGlucoseValues,
            .loginPublisherAccountById, .readPublisherLatestGlucoseValues,
        ])
        let retriedReadingsRequest = try #require(stubHTTPClient.recordedRequests.last)
        #expect(Self.queryValue(named: "sessionId", in: retriedReadingsRequest) == Self.secondSessionIdentifier)
    }

    @Test func repeatedSessionRejectionSurfacesInvalidCredentialsAndStops() async throws {
        await enqueueSuccessfulLogin(sessionIdentifier: Self.firstSessionIdentifier)
        try await enqueueFixtureError(named: "share-error-session-not-valid", for: .readPublisherLatestGlucoseValues)
        stubHTTPClient.enqueueResponse(for: .loginPublisherAccountById, responseBody: "\"\(Self.secondSessionIdentifier)\"")
        try await enqueueFixtureError(named: "share-error-session-not-valid", for: .readPublisherLatestGlucoseValues)
        let provider = makeProvider()

        await #expect(throws: GlucoseProviderError.invalidCredentials) {
            try await provider.fetchLatestReading()
        }
        let requestCountAfterFailure = stubHTTPClient.recordedRequests.count

        await #expect(throws: GlucoseProviderError.invalidCredentials) {
            try await provider.fetchLatestReading()
        }
        #expect(stubHTTPClient.recordedRequests.count == requestCountAfterFailure)
    }

    // MARK: - Authentication failures

    @Test func invalidPasswordSurfacesInvalidCredentialsWithoutRetryingLogin() async throws {
        try await enqueueFixtureError(named: "share-error-password-invalid", for: .authenticatePublisherAccount)
        let provider = makeProvider()

        await #expect(throws: GlucoseProviderError.invalidCredentials) {
            try await provider.fetchLatestReading()
        }
        testClock.advance(bySeconds: 24 * 60 * 60)
        await #expect(throws: GlucoseProviderError.invalidCredentials) {
            try await provider.fetchLatestReading()
        }

        #expect(stubHTTPClient.recordedEndpoints() == [.authenticatePublisherAccount])
    }

    @Test func allZeroSessionIdentifierIsInvalidCredentials() async throws {
        stubHTTPClient.enqueueResponse(for: .authenticatePublisherAccount, responseBody: "\"\(Self.accountIdentifier)\"")
        stubHTTPClient.enqueueResponse(
            for: .loginPublisherAccountById,
            responseBody: "\"\(DexcomShareResponseParsing.defaultIdentifier)\""
        )

        await #expect(throws: GlucoseProviderError.invalidCredentials) {
            try await makeProvider().fetchLatestReading()
        }
    }

    @Test func maximumAttemptsBacksOffBeforeNextLogin() async throws {
        try await enqueueFixtureError(named: "share-error-max-attempts", for: .authenticatePublisherAccount)
        let provider = makeProvider()

        await #expect(throws: GlucoseProviderError.accountLockedOrRateLimited) {
            try await provider.fetchLatestReading()
        }
        testClock.advance(bySeconds: 60)
        await #expect(throws: GlucoseProviderError.accountLockedOrRateLimited) {
            try await provider.fetchLatestReading()
        }
        #expect(stubHTTPClient.recordedEndpoints() == [.authenticatePublisherAccount])

        testClock.advance(bySeconds: DexcomShareLoginThrottle.maximumLoginBackoffInterval)
        await enqueueSuccessfulLogin()
        try await enqueueFixtureReadings()
        let latestReading = try await provider.fetchLatestReading()
        #expect(latestReading.valueMgPerDeciliter == 112)
    }

    @Test func httpTooManyRequestsIsRateLimited() async throws {
        stubHTTPClient.enqueueResponse(for: .authenticatePublisherAccount, statusCode: 429, responseBody: "")

        await #expect(throws: GlucoseProviderError.accountLockedOrRateLimited) {
            try await makeProvider().fetchLatestReading()
        }
    }

    // MARK: - Other failures

    @Test func emptyReadingsSurfacesNoRecentReadings() async throws {
        await enqueueSuccessfulLogin()
        stubHTTPClient.enqueueResponse(for: .readPublisherLatestGlucoseValues, responseBody: "[]")

        await #expect(throws: GlucoseProviderError.noRecentReadings) {
            try await makeProvider().fetchLatestReading()
        }
    }

    @Test func networkFailureIsNotThrottled() async throws {
        stubHTTPClient.enqueueFailure(for: .authenticatePublisherAccount, error: URLError(.notConnectedToInternet))
        let provider = makeProvider()

        await #expect(throws: GlucoseProviderError.networkUnavailable) {
            try await provider.fetchLatestReading()
        }

        await enqueueSuccessfulLogin()
        try await enqueueFixtureReadings()
        let latestReading = try await provider.fetchLatestReading()
        #expect(latestReading.valueMgPerDeciliter == 112)
    }

    @Test func cancelledRequestThrowsCancellationError() async throws {
        stubHTTPClient.enqueueFailure(for: .authenticatePublisherAccount, error: URLError(.cancelled))

        await #expect(throws: CancellationError.self) {
            try await makeProvider().fetchLatestReading()
        }
    }

    @Test func unrecognizedServerErrorIsUnexpectedResponse() async throws {
        await enqueueSuccessfulLogin()
        stubHTTPClient.enqueueResponse(
            for: .readPublisherLatestGlucoseValues,
            statusCode: 500,
            responseBody: #"{"Code":"SomethingNew","Message":"Oops"}"#
        )

        await #expect {
            try await makeProvider().fetchLatestReading()
        } throws: { thrownError in
            guard case .unexpectedResponse(let description) = thrownError as? GlucoseProviderError else {
                return false
            }
            return description.contains("SomethingNew")
        }
    }
}

struct DexcomShareLoginThrottleTests {
    let referenceDate = Date(timeIntervalSince1970: 1_690_000_000)

    @Test(arguments: [(1, 30.0), (2, 60.0), (3, 120.0), (5, 480.0), (6, 900.0), (12, 900.0)])
    func backsOffExponentiallyUpToCap(consecutiveLoginFailureCount: Int, expectedBackoffInterval: TimeInterval) {
        let backoffInterval = DexcomShareLoginThrottle.loginBackoffInterval(
            afterFailure: .unexpectedResponse(description: "test"),
            consecutiveLoginFailureCount: consecutiveLoginFailureCount
        )
        #expect(backoffInterval == expectedBackoffInterval)
    }

    @Test func networkFailuresDoNotCount() {
        var loginThrottle = DexcomShareLoginThrottle()
        loginThrottle.recordLoginFailure(.networkUnavailable, at: referenceDate)
        #expect(loginThrottle.errorPreventingLoginAttempt(at: referenceDate) == nil)
        #expect(loginThrottle.consecutiveLoginFailureCount == 0)
    }

    @Test func successResetsBackoff() {
        var loginThrottle = DexcomShareLoginThrottle()
        loginThrottle.recordLoginFailure(.unexpectedResponse(description: "test"), at: referenceDate)
        #expect(loginThrottle.errorPreventingLoginAttempt(at: referenceDate.addingTimeInterval(10)) != nil)
        #expect(loginThrottle.errorPreventingLoginAttempt(at: referenceDate.addingTimeInterval(31)) == nil)

        loginThrottle.recordLoginSuccess()
        #expect(loginThrottle.consecutiveLoginFailureCount == 0)
        #expect(loginThrottle.errorPreventingLoginAttempt(at: referenceDate) == nil)
    }
}

struct GlucoseProviderFactoryTests {
    @Test func missingUsernameMeansNoConfiguration() throws {
        let userDefaults = try #require(UserDefaults(suiteName: "GlucoseProviderFactoryTests.missingUsername"))
        userDefaults.removePersistentDomain(forName: "GlucoseProviderFactoryTests.missingUsername")

        #expect(throws: GlucoseProviderSetupError.missingConfiguration) {
            try GlucoseProviderFactory.makeGlucoseProviderFromSavedSettings(
                userDefaults: userDefaults,
                passwordStore: InMemoryPasswordStore(storedPassword: "secret"),
                httpClient: StubHTTPClient()
            )
        }
    }

    @Test func loadsSavedConfigurationWithRegion() throws {
        let userDefaults = try #require(UserDefaults(suiteName: "GlucoseProviderFactoryTests.savedConfiguration"))
        userDefaults.set("  share-user ", forKey: AppSettingsKeys.dexcomUsername)
        userDefaults.set(DexcomShareRegion.japan.rawValue, forKey: AppSettingsKeys.dexcomRegion)

        let savedConfiguration = GlucoseProviderConfiguration.loadSavedConfiguration(from: userDefaults)

        #expect(savedConfiguration == .dexcomShare(username: "share-user", region: .japan))
    }

    @Test func missingPasswordIsReported() {
        #expect(throws: GlucoseProviderSetupError.missingPassword) {
            try GlucoseProviderFactory.makeGlucoseProvider(
                for: .dexcomShare(username: "share-user", region: .unitedStates),
                passwordStore: InMemoryPasswordStore(storedPassword: nil),
                httpClient: StubHTTPClient()
            )
        }
    }

    @Test func buildsDexcomShareProvider() throws {
        let glucoseProvider = try GlucoseProviderFactory.makeGlucoseProvider(
            for: .dexcomShare(username: "share-user", region: .unitedStates),
            passwordStore: InMemoryPasswordStore(storedPassword: "secret"),
            httpClient: StubHTTPClient()
        )
        #expect(glucoseProvider.providerDisplayName == "Dexcom Share")
    }
}
