//
//  AppVersionTests.swift
//  TidebarTests
//

import Foundation
import Testing

@testable import Tidebar

struct AppVersionTests {
    @Test(
        arguments: [
            (["CFBundleShortVersionString": "1.1.0", "CFBundleVersion": "7"], "Version 1.1.0 (7)"),
            (["CFBundleShortVersionString": "2.0.0"], "Version 2.0.0 (unknown)"),
            ([:], "Version unknown (unknown)"),
        ] as [([String: String], String)])
    func readsVersionFromInfoDictionary(infoDictionary: [String: String], expectedDisplayText: String) {
        #expect(AppVersion(infoDictionary: infoDictionary).displayText == expectedDisplayText)
    }

    @Test func currentVersionComesFromTheAppBundle() {
        let currentAppVersion = AppVersion.current
        #expect(currentAppVersion.marketingVersion != AppVersion.unknownComponent)
        #expect(currentAppVersion.buildNumber != AppVersion.unknownComponent)
    }
}
