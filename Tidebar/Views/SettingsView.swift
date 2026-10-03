//
//  SettingsView.swift
//  Tidebar
//

import SwiftUI

struct SettingsView: View {
    let glucoseMonitor: GlucoseMonitor
    var passwordStore: any PasswordStore = KeychainPasswordStore.dexcomSharePasswordStore

    @AppStorage(AppSettingsKeys.dexcomUsername) private var savedUsername = ""
    @AppStorage(AppSettingsKeys.dexcomRegion) private var savedRegion = DexcomShareRegion.unitedStates
    @AppStorage(AppSettingsKeys.glucoseUnit) private var glucoseUnit = GlucoseUnit.milligramsPerDeciliter
    @AppStorage(AppSettingsKeys.launchAtLoginEnabled) private var isLaunchAtLoginEnabled = false
    @AppStorage(AppSettingsKeys.menuBarFontSizePoints) private var menuBarFontSizePoints = MenuBarTextStyle.defaultFontSizePoints
    @AppStorage(AppSettingsKeys.menuBarFontWeight) private var menuBarFontWeight = MenuBarTextStyle.defaultFontWeight
    @AppStorage(AppSettingsKeys.menuBarFontDesign) private var menuBarFontDesign = MenuBarTextStyle.defaultFontDesign

    @State private var draftUsername = ""
    @State private var draftPassword = ""
    @State private var draftRegion = DexcomShareRegion.unitedStates
    @State private var hasStoredPassword = false
    @State private var accountStatusMessage: String?
    @State private var isAwaitingConnectionResult = false
    @State private var launchAtLoginMessage: String?

    var body: some View {
        Form {
            accountSection
            displaySection
            generalSection
            versionFooterSection
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            loadAccountDrafts()
            synchronizeLaunchAtLoginPreference()
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            TextField("Username", text: $draftUsername)
                .textContentType(.username)
            SecureField("Password", text: $draftPassword, prompt: Text(passwordPrompt))
                .textContentType(.password)
            Picker("Region", selection: $draftRegion) {
                ForEach(DexcomShareRegion.allCases) { region in
                    Text(region.displayName).tag(region)
                }
            }
            HStack {
                if let displayedAccountStatusMessage {
                    Text(displayedAccountStatusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Remove Account", role: .destructive) {
                    removeAccount()
                }
                .disabled(savedUsername.isEmpty && !hasStoredPassword)
                Button("Save & Connect") {
                    saveAccountSettings()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSaveAccountSettings)
            }
        } header: {
            Text("Dexcom Share Account")
        } footer: {
            Text(
                "Use the Dexcom account that shares the data (not a follower). Share must be enabled in the Dexcom app with at least one follower."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Picker("Units", selection: $glucoseUnit) {
                ForEach(GlucoseUnit.allCases) { unit in
                    Text(unit.unitLabel).tag(unit)
                }
            }
            Picker("Font", selection: $menuBarFontDesign) {
                ForEach(MenuBarFontDesign.allCases) { fontDesign in
                    Text(fontDesign.displayName).tag(fontDesign)
                }
            }
            Picker("Weight", selection: $menuBarFontWeight) {
                ForEach(MenuBarFontWeight.allCases) { fontWeight in
                    Text(fontWeight.displayName).tag(fontWeight)
                }
            }
            LabeledContent("Size") {
                HStack {
                    Slider(value: $menuBarFontSizePoints, in: MenuBarTextStyle.fontSizePointsRange, step: 1)
                    Text("\(Int(menuBarTextStyle.fontSizePoints)) pt")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            LabeledContent("Preview") {
                HStack(spacing: 8) {
                    menuBarPreview(for: .current(Self.previewReading))
                    menuBarPreview(for: .aging(Self.previewReading))
                    Button("Reset") {
                        resetMenuBarTextStyle()
                    }
                    .disabled(menuBarTextStyle == .defaultStyle)
                }
            }
        }
    }

    // MARK: - Menu bar text style

    /// A steady reading eight minutes old: current previews ignore the age, aging previews show `8m`.
    private static let previewReading = GlucoseReading(
        valueMgPerDeciliter: 112,
        trendDirection: .flat,
        readingTimestamp: Date.distantPast
    )
    private static let previewAgeSeconds: TimeInterval = 8 * 60

    private var menuBarTextStyle: MenuBarTextStyle {
        MenuBarTextStyle(fontSizePoints: menuBarFontSizePoints, fontWeight: menuBarFontWeight, fontDesign: menuBarFontDesign)
    }

    private func menuBarPreview(for previewState: GlucoseDisplayState) -> some View {
        MenuBarStatusView(
            statusContent: GlucoseStatusFormatter.menuBarStatusContent(
                for: previewState,
                glucoseUnit: glucoseUnit,
                currentDate: Self.previewReading.readingTimestamp.addingTimeInterval(Self.previewAgeSeconds)
            ),
            widthReservingContents: GlucoseStatusFormatter.widthReservingContents(for: glucoseUnit),
            textStyle: menuBarTextStyle
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }

    private func resetMenuBarTextStyle() {
        menuBarFontSizePoints = MenuBarTextStyle.defaultFontSizePoints
        menuBarFontWeight = MenuBarTextStyle.defaultFontWeight
        menuBarFontDesign = MenuBarTextStyle.defaultFontDesign
    }

    /// An empty section whose footer shows the version, centered at the bottom of the window.
    private var versionFooterSection: some View {
        Section {
        } footer: {
            Text(AppVersion.current.displayText)
                .font(.footnote)
                .foregroundStyle(.tint)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Launch at login", isOn: launchAtLoginBinding)
            if let launchAtLoginMessage {
                Text(launchAtLoginMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Account

    private var trimmedDraftUsername: String {
        draftUsername.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// After a save, follows the monitor until the first fetch with the new account succeeds or fails.
    private var displayedAccountStatusMessage: String? {
        guard isAwaitingConnectionResult else {
            return accountStatusMessage
        }
        if let unavailableReason = glucoseMonitor.unavailableReason {
            return unavailableReason
        }
        return glucoseMonitor.lastSuccessfulFetchDate == nil ? "Saved. Connecting…" : "Connected."
    }

    private var passwordPrompt: String {
        hasStoredPassword ? "Saved in Keychain" : "Required"
    }

    private var canSaveAccountSettings: Bool {
        !trimmedDraftUsername.isEmpty && (hasStoredPassword || !draftPassword.isEmpty)
    }

    private func loadAccountDrafts() {
        draftUsername = savedUsername
        draftRegion = savedRegion
        draftPassword = ""
        hasStoredPassword = Self.passwordExists(in: passwordStore)
    }

    /// Keeps the stored password when the field is left blank.
    private func saveAccountSettings() {
        if !draftPassword.isEmpty {
            do {
                try passwordStore.savePassword(draftPassword)
            } catch {
                accountStatusMessage = "Couldn't save the password to Keychain."
                isAwaitingConnectionResult = false
                return
            }
        }
        savedUsername = trimmedDraftUsername
        savedRegion = draftRegion
        draftPassword = ""
        hasStoredPassword = Self.passwordExists(in: passwordStore)
        accountStatusMessage = nil
        isAwaitingConnectionResult = true
        glucoseMonitor.rebuildProviderAndRefresh()
    }

    private func removeAccount() {
        try? passwordStore.deletePassword()
        savedUsername = ""
        loadAccountDrafts()
        accountStatusMessage = "Account removed."
        isAwaitingConnectionResult = false
        glucoseMonitor.rebuildProviderAndRefresh()
    }

    private static func passwordExists(in passwordStore: any PasswordStore) -> Bool {
        let storedPassword = try? passwordStore.readPassword()
        return !(storedPassword ?? "").isEmpty
    }

    // MARK: - Launch at login

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { isLaunchAtLoginEnabled },
            set: { shouldLaunchAtLogin in applyLaunchAtLoginPreference(shouldLaunchAtLogin) }
        )
    }

    private func applyLaunchAtLoginPreference(_ shouldLaunchAtLogin: Bool) {
        do {
            try LaunchAtLoginController.setLaunchAtLoginEnabled(shouldLaunchAtLogin)
            isLaunchAtLoginEnabled = shouldLaunchAtLogin
            launchAtLoginMessage = approvalMessageIfNeeded()
        } catch {
            launchAtLoginMessage = "Couldn't update the login item: \(error.localizedDescription)"
        }
    }

    /// The user can remove the login item in System Settings, so mirror the system's state.
    private func synchronizeLaunchAtLoginPreference() {
        isLaunchAtLoginEnabled =
            LaunchAtLoginController.isRegisteredWithSystem
            || LaunchAtLoginController.requiresUserApproval
        launchAtLoginMessage = approvalMessageIfNeeded()
    }

    private func approvalMessageIfNeeded() -> String? {
        LaunchAtLoginController.requiresUserApproval
            ? "Approve Tidebar in System Settings › General › Login Items."
            : nil
    }
}
