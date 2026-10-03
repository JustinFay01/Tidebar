//
//  NetworkConnectivityMonitor.swift
//  Tidebar
//

import Foundation
import Network
import os

/// Reports whether the Mac has a usable network path, so fetches can be skipped while offline
/// and resumed as soon as the network returns.
nonisolated protocol NetworkConnectivityMonitoring: Sendable {
    var isNetworkAvailable: Bool { get }
    /// Yields the new availability each time it flips. Does not yield the current value on subscription.
    func connectivityChanges() -> AsyncStream<Bool>
}

/// Always online; the default where connectivity isn't wired up (e.g. most tests).
nonisolated struct AlwaysAvailableNetworkConnectivityMonitor: NetworkConnectivityMonitoring {
    let isNetworkAvailable = true

    func connectivityChanges() -> AsyncStream<Bool> {
        AsyncStream { $0.finish() }
    }
}

/// Backed by `NWPathMonitor`. Assumes the network is available until the system says otherwise,
/// so a fetch is never skipped on a guess.
nonisolated final class SystemNetworkConnectivityMonitor: NetworkConnectivityMonitoring {
    nonisolated private struct ConnectivityState: Sendable {
        var isNetworkAvailable = true
        var changeContinuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    }

    private let pathMonitor = NWPathMonitor()
    private let lockedConnectivityState = OSAllocatedUnfairLock(initialState: ConnectivityState())

    init() {
        pathMonitor.pathUpdateHandler = { [lockedConnectivityState] updatedPath in
            // `.requiresConnection` (e.g. on-demand VPN) counts as available: a request brings the path up.
            let isNetworkAvailable = updatedPath.status != .unsatisfied
            let continuationsToNotify = lockedConnectivityState.withLock { connectivityState -> [AsyncStream<Bool>.Continuation] in
                guard connectivityState.isNetworkAvailable != isNetworkAvailable else {
                    return []
                }
                connectivityState.isNetworkAvailable = isNetworkAvailable
                return Array(connectivityState.changeContinuations.values)
            }
            for changeContinuation in continuationsToNotify {
                changeContinuation.yield(isNetworkAvailable)
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.jnfcorp.Tidebar.NetworkConnectivity"))
    }

    deinit {
        pathMonitor.cancel()
    }

    var isNetworkAvailable: Bool {
        lockedConnectivityState.withLock { $0.isNetworkAvailable }
    }

    func connectivityChanges() -> AsyncStream<Bool> {
        let (changeStream, changeContinuation) = AsyncStream.makeStream(of: Bool.self)
        let subscriptionIdentifier = UUID()
        lockedConnectivityState.withLock { $0.changeContinuations[subscriptionIdentifier] = changeContinuation }
        changeContinuation.onTermination = { [lockedConnectivityState] _ in
            lockedConnectivityState.withLock { $0.changeContinuations[subscriptionIdentifier] = nil }
        }
        return changeStream
    }
}
