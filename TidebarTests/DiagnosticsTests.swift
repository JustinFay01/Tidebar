//
//  DiagnosticsTests.swift
//  TidebarTests
//

import Foundation
import Testing

@testable import Tidebar

// MARK: - Codes

struct TidebarDiagnosticCodeTests {
    @Test(arguments: TidebarDiagnosticCode.allCases)
    func codesUseCategoryDashNumberFormat(diagnosticCode: TidebarDiagnosticCode) {
        #expect(diagnosticCode.rawValue.wholeMatch(of: /[A-Z]+-\d{2}/) != nil)
        #expect(!diagnosticCode.summary.isEmpty)
    }

    @Test(arguments: [
        (GlucoseProviderError.invalidCredentials, "AUTH-01"),
        (.accountLockedOrRateLimited, "AUTH-02"),
        (.networkUnavailable, "NET-01"),
        (.noRecentReadings, "DATA-01"),
        (.unexpectedResponse(description: "anything"), "SRV-01"),
    ])
    func providerErrorsMapToStableCodes(providerError: GlucoseProviderError, expectedCode: String) {
        #expect(providerError.diagnosticCode.rawValue == expectedCode)
        #expect(providerError.statusMessage == "\(providerError.userFacingDescription) (\(expectedCode))")
    }

    @Test(arguments: [
        (GlucoseProviderSetupError.missingConfiguration, "SETUP-01"),
        (.missingPassword, "SETUP-02"),
        (.passwordUnreadable(keychainFailure: KeychainOperationError(operationStatus: errSecMissingEntitlement)), "SETUP-03"),
    ])
    func setupErrorsMapToStableCodes(setupError: GlucoseProviderSetupError, expectedCode: String) {
        #expect(setupError.diagnosticCode.rawValue == expectedCode)
        #expect(setupError.statusMessage.hasSuffix("(\(expectedCode))"))
    }

    @Test func staleReadingReasonIncludesCode() {
        #expect(GlucoseReadingFreshness.staleReadingReason(readingAgeSeconds: 1_200).hasSuffix("(DATA-02)"))
    }
}

// MARK: - Event log

struct DiagnosticEventLogTests {
    @Test func keepsOnlyMostRecentEventsOldestFirst() {
        let diagnosticEventLog = DiagnosticEventLog(capacity: 3)

        for delaySeconds in 1...5 {
            diagnosticEventLog.record(.nextFetchScheduled(delaySeconds: delaySeconds))
        }

        #expect(
            diagnosticEventLog.recentEvents.map(\.eventKind) == [
                .nextFetchScheduled(delaySeconds: 3),
                .nextFetchScheduled(delaySeconds: 4),
                .nextFetchScheduled(delaySeconds: 5),
            ])
    }

    @Test func timestampsEventsWithInjectedClock() {
        let testClock = MutableTestClock()
        let diagnosticEventLog = DiagnosticEventLog(currentDateProvider: testClock.makeDateProvider())

        diagnosticEventLog.record(.systemWoke)

        #expect(diagnosticEventLog.recentEvents.first?.eventTimestamp == testClock.currentDate)
    }

    @Test(arguments: [(0, "0s"), (45, "45s"), (60, "1m"), (315, "5m 15s"), (7_380, "2h 3m"), (-5, "0s")])
    func formatsDurations(totalSeconds: Int, expectedText: String) {
        #expect(DiagnosticEventDescriber.formatSeconds(totalSeconds) == expectedText)
    }

    @Test(
        arguments: [
            ("SessionNotValid", "SessionNotValid"),
            ("SSO_AuthenticateMaxAttemptsExceeded", "SSO_AuthenticateMaxAttemptsExceeded"),
            ("Bad Code: someone@example.com", "BadCodesomeoneexamplecom"),
            ("Ünïcode", "ncode"),
            ("!!!", nil),
            (String(repeating: "A", count: 100), String(repeating: "A", count: 64)),
        ] as [(String, String?)])
    func sanitizesServerErrorCodes(rawServerErrorCode: String, expectedSanitizedCode: String?) {
        #expect(DexcomShareResponseParsing.sanitizeServerErrorCode(rawServerErrorCode) == expectedSanitizedCode)
    }
}

// MARK: - Event recording

struct ProviderDiagnosticEventTests {
    let stubHTTPClient = StubHTTPClient()
    let diagnosticEventLog = DiagnosticEventLog()

    func makeProvider() -> DexcomShareGlucoseProvider {
        DexcomShareGlucoseProvider(
            username: "share-user",
            password: "share-password",
            region: .unitedStates,
            httpClient: stubHTTPClient,
            diagnosticEventRecorder: diagnosticEventLog
        )
    }

    func recordedKindsIgnoringDurations() -> [DiagnosticEventKind] {
        diagnosticEventLog.recentEvents.map { diagnosticEvent in
            switch diagnosticEvent.eventKind {
            case .requestCompleted(let requestName, let httpStatusCode, _, let serverErrorCode):
                .requestCompleted(
                    requestName: requestName, httpStatusCode: httpStatusCode, durationMilliseconds: 0, serverErrorCode: serverErrorCode)
            case .requestFailedInTransport(let requestName, let transportErrorCode, _):
                .requestFailedInTransport(requestName: requestName, transportErrorCode: transportErrorCode, durationMilliseconds: 0)
            default:
                diagnosticEvent.eventKind
            }
        }
    }

    @Test func recordsSignInAndRequestsOnSuccess() async throws {
        stubHTTPClient.enqueueResponse(for: .authenticatePublisherAccount, responseBody: "\"1e913fce-5a34-4d27-a991-b6cb3a3bd3d8\"")
        stubHTTPClient.enqueueResponse(for: .loginPublisherAccountById, responseBody: "\"9a1c4b52-11d8-4f0e-8a51-0c1f2b0f1e01\"")
        stubHTTPClient.enqueueResponse(
            for: .readPublisherLatestGlucoseValues, responseData: try TestFixtures.loadFixtureData(named: "share-glucose-readings"))

        _ = try await makeProvider().fetchLatestReading()

        #expect(
            recordedKindsIgnoringDurations() == [
                .signInStarted,
                .requestCompleted(
                    requestName: "General/AuthenticatePublisherAccount", httpStatusCode: 200, durationMilliseconds: 0, serverErrorCode: nil),
                .requestCompleted(
                    requestName: "General/LoginPublisherAccountById", httpStatusCode: 200, durationMilliseconds: 0, serverErrorCode: nil),
                .signInSucceeded,
                .requestCompleted(
                    requestName: "Publisher/ReadPublisherLatestGlucoseValues", httpStatusCode: 200, durationMilliseconds: 0,
                    serverErrorCode: nil),
            ])
    }

    @Test func recordsServerErrorCodeAndSignInFailure() async throws {
        stubHTTPClient.enqueueResponse(
            for: .authenticatePublisherAccount,
            statusCode: 500,
            responseData: try TestFixtures.loadFixtureData(named: "share-error-password-invalid")
        )

        await #expect(throws: GlucoseProviderError.invalidCredentials) {
            try await makeProvider().fetchLatestReading()
        }

        #expect(
            recordedKindsIgnoringDurations() == [
                .signInStarted,
                .requestCompleted(
                    requestName: "General/AuthenticatePublisherAccount", httpStatusCode: 500, durationMilliseconds: 0,
                    serverErrorCode: "AccountPasswordInvalid"),
                .signInFailed(diagnosticCode: .signInRejected),
            ])
    }

    @Test func recordsTransportErrorCode() async {
        stubHTTPClient.enqueueFailure(for: .authenticatePublisherAccount, error: URLError(.notConnectedToInternet))

        await #expect(throws: GlucoseProviderError.networkUnavailable) {
            try await makeProvider().fetchLatestReading()
        }

        #expect(
            recordedKindsIgnoringDurations().contains(
                .requestFailedInTransport(
                    requestName: "General/AuthenticatePublisherAccount",
                    transportErrorCode: URLError.Code.notConnectedToInternet.rawValue,
                    durationMilliseconds: 0
                )))
    }
}

@MainActor
struct MonitorDiagnosticEventTests {
    let testClock = MutableTestClock()
    let diagnosticEventLog = DiagnosticEventLog()

    @Test func recordsFetchLifecycle() async {
        let stubProvider = StubGlucoseProvider()
        stubProvider.enqueue(
            .success(
                GlucoseReading(
                    valueMgPerDeciliter: 112, trendDirection: .flat, readingTimestamp: testClock.currentDate.addingTimeInterval(-60))))
        stubProvider.enqueue(.failure(GlucoseProviderError.networkUnavailable))
        let monitor = GlucoseMonitor(
            providerBuilder: { .success(stubProvider) },
            currentDateProvider: testClock.makeDateProvider(),
            sleepFunction: { _ in throw CancellationError() },
            diagnosticEventRecorder: diagnosticEventLog
        )
        monitor.resetProviderAndReadings()

        _ = await monitor.performFetch()
        _ = await monitor.performFetch()

        let recordedKinds = diagnosticEventLog.recentEvents.map(\.eventKind)
        #expect(recordedKinds.first == .providerConfigured(providerName: "Stub Provider"))
        #expect(recordedKinds.contains(.fetchSucceeded(readingAgeSeconds: 60)))
        #expect(recordedKinds.contains(.nextFetchScheduled(delaySeconds: 255)))
        #expect(recordedKinds.contains(.fetchFailed(diagnosticCode: .networkUnavailable)))
        #expect(recordedKinds.last == .nextFetchScheduled(delaySeconds: 15))
        #expect(monitor.currentDiagnosticCode == .networkUnavailable)
    }

    @Test func recordsSetupFailure() {
        let monitor = GlucoseMonitor(
            providerBuilder: { .failure(.missingPassword) },
            sleepFunction: { _ in throw CancellationError() },
            diagnosticEventRecorder: diagnosticEventLog
        )

        monitor.resetProviderAndReadings()

        #expect(diagnosticEventLog.recentEvents.first?.eventKind == .providerSetupFailed(diagnosticCode: .passwordMissing))
        #expect(monitor.currentDiagnosticCode == .passwordMissing)
        #expect(monitor.diagnosticsStatus.displayStateKind == .unknown)
    }
}

// MARK: - Report

struct DiagnosticsReportBuilderTests {
    static let sampleInput = DiagnosticsReportInput(
        reportGeneratedDate: Date(timeIntervalSince1970: 1_690_000_000),
        environment: DiagnosticsEnvironment(
            appVersion: "1.0",
            appBuildNumber: "1",
            buildConfiguration: "Release",
            operatingSystemVersion: "Version 27.2 (Build 27C100)",
            hardwareArchitecture: "Apple silicon"
        ),
        settingsSummary: DiagnosticsSettingsSummary(
            isAccountConfigured: true,
            dexcomRegion: .outsideUnitedStates,
            glucoseUnit: .millimolesPerLiter,
            isLaunchAtLoginEnabled: true
        ),
        monitorStatus: GlucoseMonitorDiagnosticsStatus(
            displayStateKind: .unknown,
            currentDiagnosticCode: .networkUnavailable,
            providerDisplayName: "Dexcom Share",
            latestReadingAgeSeconds: 420,
            secondsSinceLastSuccessfulFetch: 400,
            consecutiveFetchFailureCount: 2,
            isFetchInProgress: false
        ),
        recentEvents: [
            DiagnosticEvent(
                eventTimestamp: Date(timeIntervalSince1970: 1_690_000_000), eventKind: .fetchFailed(diagnosticCode: .networkUnavailable))
        ]
    )

    @Test func includesEnvironmentSettingsStatusAndActivity() {
        let reportText = DiagnosticsReportBuilder.buildReport(from: Self.sampleInput)

        #expect(reportText.hasPrefix("Tidebar Diagnostics\n"))
        #expect(reportText.contains(DiagnosticsReportBuilder.privacyNote))
        #expect(reportText.contains("Generated: 2023-07-22T04:26:40Z"))
        #expect(reportText.contains("Tidebar: 1.0 (1), Release"))
        #expect(reportText.contains("Region: ous"))
        #expect(reportText.contains("Unit: mmol/L"))
        #expect(reportText.contains("Problem: NET-01: Could not reach Dexcom"))
        #expect(reportText.contains("Latest reading age: 7m"))
        #expect(reportText.contains("Last successful fetch: 6m 40s ago"))
        #expect(reportText.contains("2023-07-22T04:26:40Z  Fetch failed (NET-01)"))
    }

    @Test func reportsMissingValuesPlainly() {
        let emptyInput = DiagnosticsReportInput(
            reportGeneratedDate: Self.sampleInput.reportGeneratedDate,
            environment: Self.sampleInput.environment,
            settingsSummary: DiagnosticsSettingsSummary(
                isAccountConfigured: false, dexcomRegion: nil, glucoseUnit: .milligramsPerDeciliter, isLaunchAtLoginEnabled: false),
            monitorStatus: GlucoseMonitorDiagnosticsStatus(
                displayStateKind: .unknown,
                currentDiagnosticCode: nil,
                providerDisplayName: nil,
                latestReadingAgeSeconds: nil,
                secondsSinceLastSuccessfulFetch: nil,
                consecutiveFetchFailureCount: 0,
                isFetchInProgress: false
            ),
            recentEvents: []
        )

        let reportText = DiagnosticsReportBuilder.buildReport(from: emptyInput)

        #expect(reportText.contains("Region: not set"))
        #expect(reportText.contains("Problem: none"))
        #expect(reportText.contains("Provider: not configured"))
        #expect(reportText.contains("Latest reading age: none"))
        #expect(reportText.contains("Recent activity: none"))
    }

    @MainActor
    @Test func bugReportURLUsesTemplateAndCodeTitle() throws {
        let urlWithCode = try #require(DiagnosticsReporter.makeBugReportURL(diagnosticCode: .signInRejected))
        let queryItems = URLComponents(url: urlWithCode, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(urlWithCode.absoluteString.hasPrefix("https://github.com/JustinFay01/Tidebar/issues/new"))
        #expect(queryItems.contains(URLQueryItem(name: "template", value: "bug_report.yml")))
        #expect(queryItems.contains(URLQueryItem(name: "title", value: "[AUTH-01] ")))

        let urlWithoutCode = try #require(DiagnosticsReporter.makeBugReportURL(diagnosticCode: nil))
        #expect(!urlWithoutCode.absoluteString.contains("title="))
    }
}

// MARK: - Redaction

/// Runs the real provider and monitor with sentinel secrets and a distinctive glucose value, then
/// checks that none of them reach the report or the event log.
@MainActor
struct DiagnosticsRedactionTests {
    static let sentinelUsername = "sentinel-user-7f3a"
    static let sentinelPassword = "sentinel-pass-9c2e"
    static let sentinelAccountIdentifier = "5e5e5e5e-1111-4aaa-8bbb-acc0acc0acc0"
    static let sentinelFirstSessionIdentifier = "5e5e5e5e-2222-4ccc-8ddd-5e550001aaaa"
    static let sentinelSecondSessionIdentifier = "5e5e5e5e-3333-4eee-8fff-5e550002bbbb"
    static let distinctiveGlucoseValue = 347

    let testClock = MutableTestClock()
    let diagnosticEventLog: DiagnosticEventLog
    let stubHTTPClient = StubHTTPClient()

    init() {
        diagnosticEventLog = DiagnosticEventLog(currentDateProvider: testClock.makeDateProvider())
    }

    func makeProvider() -> DexcomShareGlucoseProvider {
        DexcomShareGlucoseProvider(
            username: Self.sentinelUsername,
            password: Self.sentinelPassword,
            region: .unitedStates,
            httpClient: stubHTTPClient,
            currentDateProvider: testClock.makeDateProvider(),
            diagnosticEventRecorder: diagnosticEventLog
        )
    }

    func enqueueServerTraffic() {
        // A rejected sign-in whose message echoes the username, as Dexcom's messages can.
        stubHTTPClient.enqueueResponse(
            for: .authenticatePublisherAccount,
            statusCode: 500,
            responseBody: #"{"Code":"SSO_InternalError","Message":"Cannot Authenticate by AccountName: \#(Self.sentinelUsername)"}"#
        )
        // Then a successful sign-in, an expired session, a re-login, and a reading.
        stubHTTPClient.enqueueResponse(for: .authenticatePublisherAccount, responseBody: "\"\(Self.sentinelAccountIdentifier)\"")
        stubHTTPClient.enqueueResponse(for: .loginPublisherAccountById, responseBody: "\"\(Self.sentinelFirstSessionIdentifier)\"")
        stubHTTPClient.enqueueResponse(
            for: .readPublisherLatestGlucoseValues,
            statusCode: 500,
            responseBody: #"{"Code":"SessionNotValid","Message":"Session \#(Self.sentinelFirstSessionIdentifier) expired"}"#
        )
        stubHTTPClient.enqueueResponse(for: .loginPublisherAccountById, responseBody: "\"\(Self.sentinelSecondSessionIdentifier)\"")
        let readingTimestampMilliseconds = Int64((testClock.currentDate.timeIntervalSince1970 - 90) * 1000)
        stubHTTPClient.enqueueResponse(
            for: .readPublisherLatestGlucoseValues,
            responseBody: #"[{"WT":"Date(\#(readingTimestampMilliseconds))","Value":\#(Self.distinctiveGlucoseValue),"Trend":"SingleUp"}]"#
        )
    }

    func buildReportAfterServerTraffic() async throws -> String {
        enqueueServerTraffic()

        let rejectedProvider = makeProvider()
        await #expect(throws: GlucoseProviderError.invalidCredentials) {
            try await rejectedProvider.fetchLatestReading()
        }

        let workingProvider = makeProvider()
        let monitor = GlucoseMonitor(
            providerBuilder: { .success(workingProvider) },
            currentDateProvider: testClock.makeDateProvider(),
            sleepFunction: { _ in throw CancellationError() },
            diagnosticEventRecorder: diagnosticEventLog
        )
        monitor.resetProviderAndReadings()
        _ = await monitor.performFetch()
        #expect(monitor.latestReading?.valueMgPerDeciliter == Self.distinctiveGlucoseValue)

        return DiagnosticsReportBuilder.buildReport(
            from: DiagnosticsReportInput(
                reportGeneratedDate: testClock.currentDate,
                environment: DiagnosticsReportBuilderTests.sampleInput.environment,
                settingsSummary: DiagnosticsReportBuilderTests.sampleInput.settingsSummary,
                monitorStatus: monitor.diagnosticsStatus,
                recentEvents: diagnosticEventLog.recentEvents
            )
        )
    }

    @Test func reportExcludesCredentialsIdentifiersAndGlucoseValues() async throws {
        let reportText = try await buildReportAfterServerTraffic()

        for sentinelSecret in [
            Self.sentinelUsername, Self.sentinelPassword, Self.sentinelAccountIdentifier,
            Self.sentinelFirstSessionIdentifier, Self.sentinelSecondSessionIdentifier, "Cannot Authenticate",
        ] {
            #expect(!reportText.contains(sentinelSecret), "Report leaked \(sentinelSecret)")
        }
        #expect(reportText.firstMatch(of: /\b347\b/) == nil, "Report leaked the glucose value")
    }

    @Test func reportStillExplainsWhatHappened() async throws {
        let reportText = try await buildReportAfterServerTraffic()

        #expect(reportText.contains("code SSO_InternalError"))
        #expect(reportText.contains("Sign-in failed (AUTH-01)"))
        #expect(reportText.contains("Session expired; signing in again"))
        #expect(reportText.contains("code SessionNotValid"))
        #expect(reportText.contains("Fetch succeeded; latest reading 1m 30s old"))
        #expect(reportText.contains("Display: current"))
    }
}
