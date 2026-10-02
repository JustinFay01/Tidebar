//
//  TestFixtures.swift
//  TidebarTests
//

import Foundation

private final class TestBundleMarker {}

enum TestFixtures {
    struct MissingFixtureError: Error {
        let fixtureName: String
    }

    static func loadFixtureData(named fixtureName: String) throws -> Data {
        let testBundle = Bundle(for: TestBundleMarker.self)
        guard let fixtureURL = testBundle.url(forResource: fixtureName, withExtension: "json") else {
            throw MissingFixtureError(fixtureName: fixtureName)
        }
        return try Data(contentsOf: fixtureURL)
    }
}
