//
//  HTTPClient.swift
//  Tidebar
//

import Foundation

nonisolated struct HTTPResponsePayload: Sendable {
    let statusCode: Int
    let responseBody: Data

    var isSuccessfulStatusCode: Bool {
        (200..<300).contains(statusCode)
    }
}

/// Minimal networking abstraction so providers can be tested against fixtures.
nonisolated protocol HTTPClient: Sendable {
    func performRequest(_ urlRequest: URLRequest) async throws -> HTTPResponsePayload
}

nonisolated struct URLSessionHTTPClient: HTTPClient {
    static let requestTimeoutInterval: TimeInterval = 20

    private let urlSession: URLSession

    init(urlSession: URLSession = Self.makeEphemeralURLSession()) {
        self.urlSession = urlSession
    }

    static func makeEphemeralURLSession() -> URLSession {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = requestTimeoutInterval
        sessionConfiguration.waitsForConnectivity = false
        return URLSession(configuration: sessionConfiguration)
    }

    func performRequest(_ urlRequest: URLRequest) async throws -> HTTPResponsePayload {
        let (responseBody, urlResponse) = try await urlSession.data(for: urlRequest)
        guard let httpURLResponse = urlResponse as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return HTTPResponsePayload(statusCode: httpURLResponse.statusCode, responseBody: responseBody)
    }
}
