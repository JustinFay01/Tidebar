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
    /// The password may exist, but reading it failed. `keychainFailure` carries the Security framework
    /// status (see `KeychainOperationError` for what the codes mean); it is `nil` only when a
    /// `PasswordStore` other than the Keychain one threw some other error.
    case passwordUnreadable(keychainFailure: KeychainOperationError?)

    var userFacingDescription: String {
        switch self {
        case .missingConfiguration: "Add your Dexcom account in Settings."
        case .missingPassword: "Enter your Dexcom password in Settings."
        case .passwordUnreadable(let keychainFailure?):
            "Couldn't read your password from Keychain (OSStatus \(keychainFailure.operationStatus))."
                + (keychainFailure.statusDescription.map { " \($0)" } ?? "")
        case .passwordUnreadable(nil): "Couldn't read your password from Keychain."
        }
    }
}

nonisolated enum GlucoseProviderFactory {
    static func makeGlucoseProvider(
        for configuration: GlucoseProviderConfiguration,
        passwordStore: any PasswordStore,
        httpClient: any HTTPClient,
        diagnosticEventRecorder: any DiagnosticEventRecording = DisabledDiagnosticEventRecorder()
    ) throws(GlucoseProviderSetupError) -> any GlucoseProvider {
        switch configuration {
        case .dexcomShare(let username, let region):
            let storedPassword: String?
            do {
                storedPassword = try passwordStore.readPassword()
            } catch {
                throw .passwordUnreadable(keychainFailure: error as? KeychainOperationError)
            }
            guard let storedPassword, !storedPassword.isEmpty else {
                throw .missingPassword
            }
            return DexcomShareGlucoseProvider(
                username: username,
                password: storedPassword,
                region: region,
                httpClient: httpClient,
                diagnosticEventRecorder: diagnosticEventRecorder
            )
        }
    }

    /// Builds the provider from what the user saved in Settings.
    static func makeGlucoseProviderFromSavedSettings(
        userDefaults: UserDefaults = .standard,
        passwordStore: any PasswordStore = KeychainPasswordStore.dexcomSharePasswordStore,
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        diagnosticEventRecorder: any DiagnosticEventRecording = DisabledDiagnosticEventRecorder()
    ) throws(GlucoseProviderSetupError) -> any GlucoseProvider {
        guard let savedConfiguration = GlucoseProviderConfiguration.loadSavedConfiguration(from: userDefaults) else {
            throw .missingConfiguration
        }
        return try makeGlucoseProvider(
            for: savedConfiguration,
            passwordStore: passwordStore,
            httpClient: httpClient,
            diagnosticEventRecorder: diagnosticEventRecorder
        )
    }
}
