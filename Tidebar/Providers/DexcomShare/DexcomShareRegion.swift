//
//  DexcomShareRegion.swift
//  Tidebar
//

import Foundation

/// Share API regions. Base URLs and application IDs come from pydexcom's `const.py`.
nonisolated enum DexcomShareRegion: String, CaseIterable, Identifiable, Sendable {
    case unitedStates = "us"
    case outsideUnitedStates = "ous"
    case japan = "jp"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unitedStates: "United States"
        case .outsideUnitedStates: "Outside United States"
        case .japan: "Japan"
        }
    }

    var baseURLString: String {
        switch self {
        case .unitedStates: "https://share2.dexcom.com/ShareWebServices/Services/"
        case .outsideUnitedStates: "https://shareous1.dexcom.com/ShareWebServices/Services/"
        case .japan: "https://share.dexcom.jp/ShareWebServices/Services/"
        }
    }

    var applicationIdentifier: String {
        switch self {
        case .unitedStates, .outsideUnitedStates: "d89443d2-327c-4a6f-89e5-496bbb0317db"
        case .japan: "d8665ade-9673-4e27-9ff6-92db4ce13d13"
        }
    }
}

nonisolated enum DexcomShareEndpoint: String, Sendable {
    case authenticatePublisherAccount = "General/AuthenticatePublisherAccount"
    case loginPublisherAccountById = "General/LoginPublisherAccountById"
    case readPublisherLatestGlucoseValues = "Publisher/ReadPublisherLatestGlucoseValues"
}
