//
//  DexcomShareGlucoseProvider.swift
//  Tidebar
//

import Foundation
import os

/// Reads glucose from the unofficial Dexcom Share API, following pydexcom's protocol:
/// AuthenticatePublisherAccount → account ID, LoginPublisherAccountById → session ID,
/// then ReadPublisherLatestGlucoseValues with that session.
actor DexcomShareGlucoseProvider: GlucoseProvider {
    static let maximumLookbackMinutes = 1440
    static let maximumReadingCount = 288
    static let minutesPerSensorReading = 5

    nonisolated let providerDisplayName = "Dexcom Share"

    private static let logger = Logger(subsystem: "com.jnfcorp.Tidebar", category: "DexcomShare")

    private let username: String
    private let password: String
    private let region: DexcomShareRegion
    private let httpClient: any HTTPClient
    private let currentDateProvider: @Sendable () -> Date

    private var cachedAccountIdentifier: String?
    private var cachedSessionIdentifier: String?
    private var inFlightLoginTask: Task<String, Error>?
    private var loginThrottle = DexcomShareLoginThrottle()

    /// Signals that Dexcom rejected the session ID; handled internally by logging in again.
    private struct SessionRejectedError: Error {}

    init(
        username: String,
        password: String,
        region: DexcomShareRegion,
        httpClient: any HTTPClient,
        currentDateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.username = username
        self.password = password
        self.region = region
        self.httpClient = httpClient
        self.currentDateProvider = currentDateProvider
    }

    // MARK: - GlucoseProvider

    func fetchLatestReading() async throws -> GlucoseReading {
        let glucoseReadings = try await fetchReadingsRetryingExpiredSession(
            lookbackMinutes: Self.maximumLookbackMinutes,
            maximumReadingCount: 1
        )
        guard let latestReading = glucoseReadings.first else {
            throw GlucoseProviderError.noRecentReadings
        }
        return latestReading
    }

    func fetchRecentReadings(withinMinutes lookbackMinutes: Int) async throws -> [GlucoseReading] {
        let clampedLookbackMinutes = Self.clampLookbackMinutes(lookbackMinutes)
        return try await fetchReadingsRetryingExpiredSession(
            lookbackMinutes: clampedLookbackMinutes,
            maximumReadingCount: Self.maximumReadingCount(forLookbackMinutes: clampedLookbackMinutes)
        )
    }

    static func clampLookbackMinutes(_ lookbackMinutes: Int) -> Int {
        min(max(lookbackMinutes, 1), maximumLookbackMinutes)
    }

    static func maximumReadingCount(forLookbackMinutes lookbackMinutes: Int) -> Int {
        min(lookbackMinutes / minutesPerSensorReading + 1, maximumReadingCount)
    }

    // MARK: - Session lifecycle

    /// Uses the cached session; if Dexcom rejects it, logs in once more and retries.
    /// A second rejection right after a fresh login is treated as invalid credentials.
    private func fetchReadingsRetryingExpiredSession(
        lookbackMinutes: Int,
        maximumReadingCount: Int
    ) async throws -> [GlucoseReading] {
        let sessionIdentifier = try await obtainSessionIdentifier()
        do {
            return try await requestGlucoseReadings(
                sessionIdentifier: sessionIdentifier,
                lookbackMinutes: lookbackMinutes,
                maximumReadingCount: maximumReadingCount
            )
        } catch is SessionRejectedError {
            Self.logger.info("Dexcom Share session expired; signing in again")
            discardCachedSession(ifMatching: sessionIdentifier)
        }

        let refreshedSessionIdentifier = try await obtainSessionIdentifier()
        do {
            return try await requestGlucoseReadings(
                sessionIdentifier: refreshedSessionIdentifier,
                lookbackMinutes: lookbackMinutes,
                maximumReadingCount: maximumReadingCount
            )
        } catch is SessionRejectedError {
            Self.logger.error("Dexcom Share rejected a freshly created session")
            discardCachedSession(ifMatching: refreshedSessionIdentifier)
            loginThrottle.recordLoginFailure(.invalidCredentials, at: currentDateProvider())
            throw GlucoseProviderError.invalidCredentials
        }
    }

    private func discardCachedSession(ifMatching rejectedSessionIdentifier: String) {
        if cachedSessionIdentifier == rejectedSessionIdentifier {
            cachedSessionIdentifier = nil
        }
    }

    /// Returns the cached session ID, or logs in. Concurrent callers share one in-flight login.
    private func obtainSessionIdentifier() async throws -> String {
        if let cachedSessionIdentifier {
            return cachedSessionIdentifier
        }
        if let inFlightLoginTask {
            return try await inFlightLoginTask.value
        }
        let loginTask = Task { try await self.performThrottledLogin() }
        inFlightLoginTask = loginTask
        defer { inFlightLoginTask = nil }
        let sessionIdentifier = try await loginTask.value
        cachedSessionIdentifier = sessionIdentifier
        return sessionIdentifier
    }

    private func performThrottledLogin() async throws -> String {
        if let throttledLoginError = loginThrottle.errorPreventingLoginAttempt(at: currentDateProvider()) {
            Self.logger.info("Skipping Dexcom Share sign-in while backing off")
            throw throttledLoginError
        }
        do {
            let accountIdentifier = try await obtainAccountIdentifier()
            let sessionIdentifier = try await requestSessionIdentifier(accountIdentifier: accountIdentifier)
            loginThrottle.recordLoginSuccess()
            return sessionIdentifier
        } catch let loginFailure as GlucoseProviderError {
            Self.logger.error("Dexcom Share sign-in failed: \(String(describing: loginFailure), privacy: .public)")
            loginThrottle.recordLoginFailure(loginFailure, at: currentDateProvider())
            if loginFailure == .invalidCredentials {
                cachedAccountIdentifier = nil
            }
            throw loginFailure
        }
    }

    private func obtainAccountIdentifier() async throws -> String {
        if let cachedAccountIdentifier {
            return cachedAccountIdentifier
        }
        let accountIdentifier = try await requestAccountIdentifier()
        cachedAccountIdentifier = accountIdentifier
        return accountIdentifier
    }

    // MARK: - Endpoint requests

    private struct AuthenticatePublisherAccountRequestBody: Encodable {
        let accountName: String
        let password: String
        let applicationId: String
    }

    private struct LoginPublisherAccountByIdRequestBody: Encodable {
        let accountId: String
        let password: String
        let applicationId: String
    }

    private struct EmptyRequestBody: Encodable {}

    private func requestAccountIdentifier() async throws -> String {
        Self.logger.info("Signing in to Dexcom Share (\(self.region.rawValue, privacy: .public))")
        let requestBody = AuthenticatePublisherAccountRequestBody(
            accountName: username,
            password: password,
            applicationId: region.applicationIdentifier
        )
        let responseBody = try await sendPostRequest(to: .authenticatePublisherAccount, jsonBody: requestBody)
        return try parseRequiredIdentifier(fromResponseData: responseBody)
    }

    private func requestSessionIdentifier(accountIdentifier: String) async throws -> String {
        let requestBody = LoginPublisherAccountByIdRequestBody(
            accountId: accountIdentifier,
            password: password,
            applicationId: region.applicationIdentifier
        )
        let responseBody = try await sendPostRequest(to: .loginPublisherAccountById, jsonBody: requestBody)
        return try parseRequiredIdentifier(fromResponseData: responseBody)
    }

    private func requestGlucoseReadings(
        sessionIdentifier: String,
        lookbackMinutes: Int,
        maximumReadingCount: Int
    ) async throws -> [GlucoseReading] {
        let queryItems = [
            URLQueryItem(name: "sessionId", value: sessionIdentifier),
            URLQueryItem(name: "minutes", value: String(lookbackMinutes)),
            URLQueryItem(name: "maxCount", value: String(maximumReadingCount)),
        ]
        let responseBody = try await sendPostRequest(
            to: .readPublisherLatestGlucoseValues,
            queryItems: queryItems,
            jsonBody: EmptyRequestBody()
        )
        return try DexcomShareResponseParsing.parseGlucoseReadings(fromResponseData: responseBody)
    }

    /// An all-zero identifier means Dexcom did not accept the credentials.
    private func parseRequiredIdentifier(fromResponseData responseData: Data) throws -> String {
        guard let identifier = try DexcomShareResponseParsing.parseIdentifier(fromResponseData: responseData) else {
            throw GlucoseProviderError.invalidCredentials
        }
        return identifier
    }

    // MARK: - Transport

    private func sendPostRequest(
        to endpoint: DexcomShareEndpoint,
        queryItems: [URLQueryItem] = [],
        jsonBody: some Encodable
    ) async throws -> Data {
        let urlRequest = try makePostRequest(to: endpoint, queryItems: queryItems, jsonBody: jsonBody)
        let responsePayload = try await performRequestMappingTransportErrors(urlRequest)
        guard responsePayload.isSuccessfulStatusCode else {
            throw Self.mapFailedResponse(responsePayload, endpoint: endpoint)
        }
        return responsePayload.responseBody
    }

    private func makePostRequest(
        to endpoint: DexcomShareEndpoint,
        queryItems: [URLQueryItem],
        jsonBody: some Encodable
    ) throws -> URLRequest {
        guard var urlComponents = URLComponents(string: region.baseURLString + endpoint.rawValue) else {
            throw GlucoseProviderError.unexpectedResponse(description: "Invalid Dexcom Share URL.")
        }
        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }
        guard let endpointURL = urlComponents.url else {
            throw GlucoseProviderError.unexpectedResponse(description: "Invalid Dexcom Share URL.")
        }
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(jsonBody)
        return urlRequest
    }

    private func performRequestMappingTransportErrors(_ urlRequest: URLRequest) async throws -> HTTPResponsePayload {
        do {
            return try await httpClient.performRequest(urlRequest)
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw GlucoseProviderError.networkUnavailable
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GlucoseProviderError.unexpectedResponse(description: "Request failed.")
        }
    }

    private static let tooManyRequestsStatusCode = 429

    private static func mapFailedResponse(_ responsePayload: HTTPResponsePayload, endpoint: DexcomShareEndpoint) -> Error {
        if responsePayload.statusCode == tooManyRequestsStatusCode {
            return GlucoseProviderError.accountLockedOrRateLimited
        }
        let serverFailure = DexcomShareResponseParsing.parseServerFailure(fromResponseData: responsePayload.responseBody)
        switch serverFailure {
        case .sessionExpiredOrInvalid:
            return SessionRejectedError()
        case .invalidCredentials:
            return GlucoseProviderError.invalidCredentials
        case .maximumAuthenticationAttemptsExceeded:
            return GlucoseProviderError.accountLockedOrRateLimited
        case .unrecognized(let code):
            logger.error("Dexcom Share \(endpoint.rawValue, privacy: .public) failed: HTTP \(responsePayload.statusCode), code \(code ?? "none", privacy: .public)")
            return GlucoseProviderError.unexpectedResponse(
                description: "Dexcom returned HTTP \(responsePayload.statusCode) (\(code ?? "no error code"))."
            )
        }
    }
}
