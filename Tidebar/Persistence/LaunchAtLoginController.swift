//
//  LaunchAtLoginController.swift
//  Tidebar
//

import Foundation
import ServiceManagement

/// Registers the app as a login item. The system's status is the source of truth; the
/// `@AppStorage` preference mirrors it so the Settings toggle reflects the user's choice.
enum LaunchAtLoginController {
    static var isRegisteredWithSystem: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var requiresUserApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setLaunchAtLoginEnabled(_ shouldLaunchAtLogin: Bool) throws {
        if shouldLaunchAtLogin {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
