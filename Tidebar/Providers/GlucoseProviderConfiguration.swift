//
//  GlucoseProviderConfiguration.swift
//  Tidebar
//

import Foundation

/// Non-secret description of which provider to use. Secrets are read from the Keychain by the factory.
nonisolated enum GlucoseProviderConfiguration: Equatable, Sendable {
    case dexcomShare(username: String, region: DexcomShareRegion)

    /// Reads the saved configuration, or `nil` when no account has been set up.
    static func loadSavedConfiguration(from userDefaults: UserDefaults) -> GlucoseProviderConfiguration? {
        let savedUsername = (userDefaults.string(forKey: AppSettingsKeys.dexcomUsername) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !savedUsername.isEmpty else {
            return nil
        }
        let savedRegion =
            userDefaults.string(forKey: AppSettingsKeys.dexcomRegion)
            .flatMap(DexcomShareRegion.init(rawValue:)) ?? .unitedStates
        return .dexcomShare(username: savedUsername, region: savedRegion)
    }
}

nonisolated enum GlucoseProviderSetupError: Error, Equatable {
    case missingConfiguration
    case missingPassword

    var userFacingDescription: String {
        switch self {
        case .missingConfiguration: "Add your Dexcom account in Settings."
        case .missingPassword: "Enter your Dexcom password in Settings."
        }
    }
}

nonisolated enum GlucoseProviderFactory {
    static func makeGlucoseProvider(
        for configuration: GlucoseProviderConfiguration,
        passwordStore: any PasswordStore,
        httpClient: any HTTPClient
    ) throws(GlucoseProviderSetupError) -> any GlucoseProvider {
        switch configuration {
        case .dexcomShare(let username, let region):
            let storedPassword = try? passwordStore.readPassword()
            guard let storedPassword, !storedPassword.isEmpty else {
                throw .missingPassword
            }
            return DexcomShareGlucoseProvider(
                username: username,
                password: storedPassword,
                region: region,
                httpClient: httpClient
            )
        }
    }

    /// Builds the provider from what the user saved in Settings.
    static func makeGlucoseProviderFromSavedSettings(
        userDefaults: UserDefaults = .standard,
        passwordStore: any PasswordStore = KeychainPasswordStore.dexcomSharePasswordStore,
        httpClient: any HTTPClient = URLSessionHTTPClient()
    ) throws(GlucoseProviderSetupError) -> any GlucoseProvider {
        guard let savedConfiguration = GlucoseProviderConfiguration.loadSavedConfiguration(from: userDefaults) else {
            throw .missingConfiguration
        }
        return try makeGlucoseProvider(for: savedConfiguration, passwordStore: passwordStore, httpClient: httpClient)
    }
}
