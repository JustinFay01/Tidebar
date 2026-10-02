//
//  AppSettingsKeys.swift
//  Tidebar
//

import Foundation

/// UserDefaults keys used with `@AppStorage`. Secrets never go here; see `KeychainPasswordStore`.
nonisolated enum AppSettingsKeys {
    static let dexcomUsername = "dexcomUsername"
    static let dexcomRegion = "dexcomRegion"
    static let glucoseUnit = "glucoseUnit"
    static let launchAtLoginEnabled = "launchAtLoginEnabled"
    static let menuBarFontSizePoints = "menuBarFontSizePoints"
    static let menuBarFontWeight = "menuBarFontWeight"
    static let menuBarFontDesign = "menuBarFontDesign"
}
