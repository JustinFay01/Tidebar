//
//  TestDoubles.swift
//  TidebarTests
//

import Foundation
import os

@testable import Tidebar

/// A clock tests can advance. Thread-safe so it can back `@Sendable` date providers.
final class MutableTestClock: Sendable {
    private let lockedCurrentDate: OSAllocatedUnfairLock<Date>

    init(startingAt startDate: Date = Date(timeIntervalSince1970: 1_690_000_000)) {
        lockedCurrentDate = OSAllocatedUnfairLock(initialState: startDate)
    }

    var currentDate: Date {
        lockedCurrentDate.withLock { $0 }
    }

    func advance(bySeconds secondsToAdvance: TimeInterval) {
        lockedCurrentDate.withLock { $0 = $0.addingTimeInterval(secondsToAdvance) }
    }

    func makeDateProvider() -> @Sendable () -> Date {
        { [self] in currentDate }
    }
}

/// Returns queued responses per Share endpoint and records every request it receives.
final class StubHTTPClient: HTTPClient {
    private struct StubState {
        var queuedResultsByEndpoint: [DexcomShareEndpoint: [Result<HTTPResponsePayload, Error>]] = [:]
        var recordedRequests: [URLRequest] = []
    }

    private let lockedStubState = OSAllocatedUnfairLock(uncheckedState: StubState())

    var recordedRequests: [URLRequest] {
        lockedStubState.withLock { $0.recordedRequests }
    }

    func enqueueResponse(for endpoint: DexcomShareEndpoint, statusCode: Int = 200, responseBody: String) {
        enqueueResult(.success(HTTPResponsePayload(statusCode: statusCode, responseBody: Data(responseBody.utf8))), for: endpoint)
    }

    func enqueueResponse(for endpoint: DexcomShareEndpoint, statusCode: Int = 200, responseData: Data) {
        enqueueResult(.success(HTTPResponsePayload(statusCode: statusCode, responseBody: responseData)), for: endpoint)
    }

    func enqueueFailure(for endpoint: DexcomShareEndpoint, error: Error) {
        enqueueResult(.failure(error), for: endpoint)
    }

    func recordedEndpoints() -> [DexcomShareEndpoint] {
        recordedRequests.compactMap(Self.endpoint(for:))
    }

    func performRequest(_ urlRequest: URLRequest) async throws -> HTTPResponsePayload {
        let nextResult = lockedStubState.withLock { stubState -> Result<HTTPResponsePayload, Error>? in
            stubState.recordedRequests.append(urlRequest)
            guard let endpoint = Self.endpoint(for: urlRequest),
                var queuedResults = stubState.queuedResultsByEndpoint[endpoint],
                !queuedResults.isEmpty
            else {
                return nil
            }
            let nextResult = queuedResults.removeFirst()
            stubState.queuedResultsByEndpoint[endpoint] = queuedResults
            return nextResult
        }
        guard let nextResult else {
            throw UnexpectedStubRequestError(requestURL: urlRequest.url)
        }
        return try nextResult.get()
    }

    private func enqueueResult(_ queuedResult: Result<HTTPResponsePayload, Error>, for endpoint: DexcomShareEndpoint) {
        lockedStubState.withLock { $0.queuedResultsByEndpoint[endpoint, default: []].append(queuedResult) }
    }

    private static func endpoint(for urlRequest: URLRequest) -> DexcomShareEndpoint? {
        guard let requestURL = urlRequest.url else {
            return nil
        }
        let endpointPath = requestURL.pathComponents.suffix(2).joined(separator: "/")
        return DexcomShareEndpoint(rawValue: endpointPath)
    }

    struct UnexpectedStubRequestError: Error {
        let requestURL: URL?
    }
}

final class InMemoryPasswordStore: PasswordStore {
    private let lockedPassword: OSAllocatedUnfairLock<String?>

    init(storedPassword: String? = nil) {
        lockedPassword = OSAllocatedUnfairLock(initialState: storedPassword)
    }

    func readPassword() throws -> String? {
        lockedPassword.withLock { $0 }
    }

    func savePassword(_ password: String) throws {
        lockedPassword.withLock { $0 = password }
    }

    func deletePassword() throws {
        lockedPassword.withLock { $0 = nil }
    }
}
