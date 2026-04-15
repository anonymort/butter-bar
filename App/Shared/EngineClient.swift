import Foundation
import EngineInterface

// MARK: - Error type

public enum EngineClientError: Error {
    /// Attempted an XPC call before `connect()` or after invalidation.
    case notConnected
    /// The XPC proxy itself reported a connection error.
    case serviceError(NSError)
}

// MARK: - EngineClient

/// App-side actor that owns the `NSXPCConnection` to the EngineService XPC process.
///
/// Lifecycle:
/// - Call `connect()` once at app start. The actor keeps one connection for the
///   app's lifetime, reconnecting automatically after invalidation.
/// - After interruption (engine crash/restart with connection still technically valid)
///   the actor re-subscribes for events without creating a new connection object.
/// - All `EngineXPC` methods are exposed as `async throws` wrappers that bridge
///   the reply-block API to Swift concurrency.
public actor EngineClient {

    // MARK: Private state

    private var connection: NSXPCConnection?
    private var eventHandler: EngineEventHandler?

    // MARK: Init

    public init() {}

    // MARK: - Connection lifecycle

    /// Creates and resumes the XPC connection to the EngineService.
    /// Safe to call from any async context; must not be called while already connected.
    public func connect() {
        let conn = NSXPCConnection(serviceName: "com.butterbar.app.EngineService")

        // Engine exports EngineXPC; app exports EngineEvents for event callbacks.
        conn.remoteObjectInterface = XPCInterfaceFactory.engineInterface()
        conn.exportedInterface = XPCInterfaceFactory.eventsInterface()

        let handler = EngineEventHandler()
        conn.exportedObject = handler
        eventHandler = handler

        // Capture self weakly so these closures don't keep the actor alive.
        conn.invalidationHandler = { [weak self] in
            Task { await self?.handleInvalidation() }
        }
        conn.interruptionHandler = { [weak self] in
            Task { await self?.handleInterruption() }
        }

        conn.resume()
        connection = conn

        // Subscribe immediately so the engine can push events.
        Task { try? await subscribe() }
    }

    /// Tears down the connection without triggering automatic reconnect.
    /// Use during app termination.
    public func disconnect() {
        connection?.invalidate()
        connection = nil
        eventHandler = nil
    }

    // MARK: - Async wrappers

    /// Returns the current list of torrents known to the engine.
    public func listTorrents() async throws -> [TorrentSummaryDTO] {
        let p = try proxy()
        return try await withCheckedThrowingContinuation { cont in
            p.listTorrents { summaries in
                cont.resume(returning: summaries)
            }
        }
    }

    /// Adds a torrent by magnet link. Returns the initial `TorrentSummaryDTO`.
    public func addMagnet(_ magnet: String) async throws -> TorrentSummaryDTO {
        let p = try proxy()
        return try await withCheckedThrowingContinuation { cont in
            p.addMagnet(magnet) { dto, error in
                if let error {
                    cont.resume(throwing: EngineClientError.serviceError(error))
                } else if let dto {
                    cont.resume(returning: dto)
                } else {
                    cont.resume(throwing: EngineClientError.serviceError(
                        NSError(domain: EngineErrorDomain,
                                code: EngineErrorCode.notImplemented.rawValue,
                                userInfo: [NSLocalizedDescriptionKey: "addMagnet returned nil without error"])))
                }
            }
        }
    }

    /// Adds a torrent from a security-scoped bookmark. Returns the initial `TorrentSummaryDTO`.
    public func addTorrentFile(_ bookmarkData: NSData) async throws -> TorrentSummaryDTO {
        let p = try proxy()
        return try await withCheckedThrowingContinuation { cont in
            p.addTorrentFile(bookmarkData) { dto, error in
                if let error {
                    cont.resume(throwing: EngineClientError.serviceError(error))
                } else if let dto {
                    cont.resume(returning: dto)
                } else {
                    cont.resume(throwing: EngineClientError.serviceError(
                        NSError(domain: EngineErrorDomain,
                                code: EngineErrorCode.notImplemented.rawValue,
                                userInfo: [NSLocalizedDescriptionKey: "addTorrentFile returned nil without error"])))
                }
            }
        }
    }

    /// Removes a torrent, optionally deleting downloaded data.
    public func removeTorrent(_ torrentID: NSString, deleteData: Bool) async throws {
        let p = try proxy()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            p.removeTorrent(torrentID, deleteData: deleteData) { error in
                if let error {
                    cont.resume(throwing: EngineClientError.serviceError(error))
                } else {
                    cont.resume()
                }
            }
        }
    }

    /// Lists the files contained in a multi-file torrent.
    public func listFiles(_ torrentID: NSString) async throws -> [TorrentFileDTO] {
        let p = try proxy()
        return try await withCheckedThrowingContinuation { cont in
            p.listFiles(torrentID) { files, error in
                if let error {
                    cont.resume(throwing: EngineClientError.serviceError(error))
                } else {
                    cont.resume(returning: files)
                }
            }
        }
    }

    /// Marks a subset of files as wanted (prioritised for download).
    public func setWantedFiles(_ torrentID: NSString, fileIndexes: [NSNumber]) async throws {
        let p = try proxy()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            p.setWantedFiles(torrentID, fileIndexes: fileIndexes) { error in
                if let error {
                    cont.resume(throwing: EngineClientError.serviceError(error))
                } else {
                    cont.resume()
                }
            }
        }
    }

    /// Opens a playback stream for a file. Returns a `StreamDescriptorDTO` with the loopback URL.
    public func openStream(_ torrentID: NSString, fileIndex: NSNumber) async throws -> StreamDescriptorDTO {
        let p = try proxy()
        return try await withCheckedThrowingContinuation { cont in
            p.openStream(torrentID, fileIndex: fileIndex) { dto, error in
                if let error {
                    cont.resume(throwing: EngineClientError.serviceError(error))
                } else if let dto {
                    cont.resume(returning: dto)
                } else {
                    cont.resume(throwing: EngineClientError.serviceError(
                        NSError(domain: EngineErrorDomain,
                                code: EngineErrorCode.streamOpenFailed.rawValue,
                                userInfo: [NSLocalizedDescriptionKey: "openStream returned nil without error"])))
                }
            }
        }
    }

    /// Closes a previously-opened stream.
    public func closeStream(_ streamID: NSString) async throws {
        let p = try proxy()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.closeStream(streamID) {
                cont.resume()
            }
        }
    }

    // MARK: - Event stream access

    /// The event handler that receives engine-pushed events.
    /// Callers observe its publishers to react to engine state changes.
    public var events: EngineEventHandler? { eventHandler }

    // MARK: - Private helpers

    /// Returns the remote proxy with an error handler.
    /// The error handler fires on connection failure after the call has been enqueued;
    /// it does not race with `notConnected` — that check is synchronous.
    private func proxy() throws -> any EngineXPC {
        guard let conn = connection else {
            throw EngineClientError.notConnected
        }
        // remoteObjectProxyWithErrorHandler is preferred over bare remoteObjectProxy:
        // it gives a callback if the message cannot be delivered after queuing.
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            NSLog("[EngineClient] XPC proxy error: %@", error.localizedDescription)
        }) as? any EngineXPC else {
            throw EngineClientError.notConnected
        }
        return proxy
    }

    /// Called when the XPC connection is fully invalidated (engine process died or was killed).
    /// Creates a fresh `NSXPCConnection` after a brief back-off.
    private func handleInvalidation() {
        connection = nil
        eventHandler = nil
        NSLog("[EngineClient] XPC connection invalidated — reconnecting in 500 ms")
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            connect()
        }
    }

    /// Called on XPC interruption (connection still valid; engine may have crashed and restarted).
    /// Re-subscribes so the engine has a fresh reference to the event handler.
    private func handleInterruption() {
        NSLog("[EngineClient] XPC connection interrupted — re-subscribing")
        Task { try? await subscribe() }
    }

    /// Sends the local `EngineEventHandler` to the engine so it can push events back.
    private func subscribe() async throws {
        guard let handler = eventHandler else { return }
        let p = try proxy()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            p.subscribe(handler) { error in
                if let error {
                    cont.resume(throwing: EngineClientError.serviceError(error))
                } else {
                    cont.resume()
                }
            }
        }
    }
}
