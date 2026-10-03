//
//  AppVersion.swift
//  Tidebar
//

import Foundation

/// The app's marketing version and build number, as stamped into Info.plist by the release script.
nonisolated struct AppVersion: Equatable, Sendable {
    static let unknownComponent = "unknown"

    let marketingVersion: String
    let buildNumber: String

    static var current: AppVersion {
        AppVersion(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    init(marketingVersion: String, buildNumber: String) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
    }

    init(infoDictionary: [String: Any]) {
        self.init(
            marketingVersion: infoDictionary["CFBundleShortVersionString"] as? String ?? Self.unknownComponent,
            buildNumber: infoDictionary["CFBundleVersion"] as? String ?? Self.unknownComponent
        )
    }

    /// e.g. "Version 1.1.0 (7)"
    var displayText: String {
        "Version \(marketingVersion) (\(buildNumber))"
    }
}
