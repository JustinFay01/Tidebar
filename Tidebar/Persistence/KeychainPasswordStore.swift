//
//  KeychainPasswordStore.swift
//  Tidebar
//

import Foundation
import Security

nonisolated protocol PasswordStore: Sendable {
    func readPassword() throws -> String?
    func savePassword(_ password: String) throws
    func deletePassword() throws
}

/// A failed `SecItem` call. `operationStatus` is the `OSStatus` the Security framework returned:
/// one of the `errSec…` constants declared in `<Security/SecBase.h>` and listed in Apple's
/// "Security Framework Result Codes". The ones this store is likely to hit:
///
/// | Value  | Constant                      | Meaning here                                                     |
/// |--------|-------------------------------|------------------------------------------------------------------|
/// | -34018 | `errSecMissingEntitlement`    | Build lacks the keychain access group (ad-hoc signed, no profile) |
/// | -25308 | `errSecInteractionNotAllowed` | Keychain is locked, e.g. before first unlock after a restart      |
/// | -25293 | `errSecAuthFailed`            | The system denied access to the item                              |
/// | -128   | `errSecUserCanceled`          | The user dismissed a Keychain prompt                              |
///
/// `errSecItemNotFound` (-25300) never appears here: the store treats it as "no password saved".
nonisolated struct KeychainOperationError: Error, Equatable {
    let operationStatus: OSStatus

    /// The system's own description of `operationStatus`, e.g. "A required entitlement is not present."
    var statusDescription: String? {
        SecCopyErrorMessageString(operationStatus, nil) as String?
    }
}

/// Stores a single generic password in the user's data protection keychain, not the legacy
/// file-based login keychain. That needs the `keychain-access-groups` entitlement, which only a
/// build signed with a development team can carry; ad-hoc builds fail with `errSecMissingEntitlement`.
nonisolated struct KeychainPasswordStore: PasswordStore {
    static let dexcomSharePasswordStore = KeychainPasswordStore(
        serviceName: "com.jnfcorp.Tidebar.dexcom-share",
        accountName: "dexcom-share-password"
    )

    let serviceName: String
    let accountName: String

    func readPassword() throws -> String? {
        var readQuery = makeBaseQuery()
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var readResult: CFTypeRef?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &readResult)
        if readStatus == errSecItemNotFound {
            return nil
        }
        guard readStatus == errSecSuccess, let passwordData = readResult as? Data else {
            throw KeychainOperationError(operationStatus: readStatus)
        }
        return String(data: passwordData, encoding: .utf8)
    }

    func savePassword(_ password: String) throws {
        let passwordData = Data(password.utf8)
        let updateStatus = SecItemUpdate(
            makeBaseQuery() as CFDictionary,
            [kSecValueData as String: passwordData] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainOperationError(operationStatus: updateStatus)
        }
        try addNewPasswordItem(passwordData: passwordData)
    }

    func deletePassword() throws {
        let deleteStatus = SecItemDelete(makeBaseQuery() as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainOperationError(operationStatus: deleteStatus)
        }
    }

    private func addNewPasswordItem(passwordData: Data) throws {
        var addQuery = makeBaseQuery()
        addQuery[kSecValueData as String] = passwordData
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainOperationError(operationStatus: addStatus)
        }
    }

    private func makeBaseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
