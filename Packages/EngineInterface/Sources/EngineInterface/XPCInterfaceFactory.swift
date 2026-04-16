import Foundation

/// Creates configured NSXPCInterface instances for EngineXPC and EngineEvents.
///
/// Missing class registrations cause silent decode failures at XPC runtime — this
/// factory is the single place that owns all registrations, and the companion test
/// verifies every method has at least one registration.
public enum XPCInterfaceFactory {

    // MARK: - Private helpers

    /// Wraps an ObjC class metatype into AnyHashable for use with NSXPCInterface.setClasses.
    /// ObjC class objects are NSObject instances, so this cast is always safe.
    private static func h(_ cls: AnyClass) -> AnyHashable {
        cls as AnyObject as! AnyHashable
    }

    // MARK: - EngineXPC interface

    /// Returns a fully-configured NSXPCInterface for the EngineXPC protocol.
    ///
    /// Selector argument-index mapping (0-based, excludes the trailing reply block):
    ///
    /// addMagnet(_:reply:)
    ///   reply arg 0 — TorrentSummaryDTO?
    ///
    /// addTorrentFile(_:reply:)
    ///   reply arg 0 — TorrentSummaryDTO?
    ///
    /// listTorrents(_:)
    ///   reply arg 0 — [TorrentSummaryDTO]  (NSArray<TorrentSummaryDTO>)
    ///
    /// removeTorrent(_:deleteData:reply:)
    ///   (reply has only NSError? — no custom class registration needed)
    ///
    /// listFiles(_:reply:)
    ///   reply arg 0 — [TorrentFileDTO]  (NSArray<TorrentFileDTO>)
    ///
    /// setWantedFiles(_:fileIndexes:reply:)
    ///   arg 1 — [NSNumber] (fileIndexes)
    ///   (reply has only NSError? — no custom class registration needed)
    ///
    /// openStream(_:fileIndex:reply:)
    ///   reply arg 0 — StreamDescriptorDTO?
    ///
    /// closeStream(_:reply:)
    ///   (reply is Void — no registration needed)
    ///
    /// listPlaybackHistory(_:)
    ///   reply arg 0 — [PlaybackHistoryDTO]  (NSArray<PlaybackHistoryDTO>)
    ///   PlaybackHistoryDTO.completedAt is NSNumber? — register NSNumber too.
    ///
    /// setWatchedState(_:fileIndex:watched:reply:)
    ///   (reply has only NSError? — no custom class registration needed)
    ///
    /// subscribe(_:reply:)
    ///   arg 0 — EngineEvents proxy (set via setInterface, not setClasses)
    public static func engineInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: EngineXPC.self)

        // addMagnet(_:reply:) — reply arg 0: TorrentSummaryDTO?
        interface.setClasses(
            [h(TorrentSummaryDTO.self)],
            for: #selector(EngineXPC.addMagnet(_:reply:)),
            argumentIndex: 0,
            ofReply: true
        )

        // addTorrentFile(_:reply:) — reply arg 0: TorrentSummaryDTO?
        interface.setClasses(
            [h(TorrentSummaryDTO.self)],
            for: #selector(EngineXPC.addTorrentFile(_:reply:)),
            argumentIndex: 0,
            ofReply: true
        )

        // listTorrents(_:) — reply arg 0: [TorrentSummaryDTO]
        interface.setClasses(
            [h(NSArray.self), h(TorrentSummaryDTO.self)],
            for: #selector(EngineXPC.listTorrents(_:)),
            argumentIndex: 0,
            ofReply: true
        )

        // listFiles(_:reply:) — reply arg 0: [TorrentFileDTO]
        interface.setClasses(
            [h(NSArray.self), h(TorrentFileDTO.self)],
            for: #selector(EngineXPC.listFiles(_:reply:)),
            argumentIndex: 0,
            ofReply: true
        )

        // setWantedFiles(_:fileIndexes:reply:) — arg 1 (fileIndexes): [NSNumber]
        interface.setClasses(
            [h(NSArray.self), h(NSNumber.self)],
            for: #selector(EngineXPC.setWantedFiles(_:fileIndexes:reply:)),
            argumentIndex: 1,
            ofReply: false
        )

        // openStream(_:fileIndex:reply:) — reply arg 0: StreamDescriptorDTO?
        interface.setClasses(
            [h(StreamDescriptorDTO.self)],
            for: #selector(EngineXPC.openStream(_:fileIndex:reply:)),
            argumentIndex: 0,
            ofReply: true
        )

        // listPlaybackHistory(_:) — reply arg 0: [PlaybackHistoryDTO]
        // PlaybackHistoryDTO carries an NSNumber? for completedAt.
        interface.setClasses(
            [h(NSArray.self), h(PlaybackHistoryDTO.self), h(NSNumber.self)],
            for: #selector(EngineXPC.listPlaybackHistory(_:)),
            argumentIndex: 0,
            ofReply: true
        )

        // setWatchedState(_:fileIndex:watched:reply:) — reply only carries
        // NSError?. No custom-class registration needed.

        // subscribe(_:reply:) — arg 0: EngineEvents proxy
        // Use setInterface so XPC knows to create a proxy object rather than deserialise a plain value.
        interface.setInterface(
            eventsInterface(),
            for: #selector(EngineXPC.subscribe(_:reply:)),
            argumentIndex: 0,
            ofReply: false
        )

        return interface
    }

    // MARK: - EngineEvents interface

    /// Returns a fully-configured NSXPCInterface for the EngineEvents protocol.
    ///
    /// torrentUpdated(_:)          — arg 0: TorrentSummaryDTO
    /// fileAvailabilityChanged(_:) — arg 0: FileAvailabilityDTO (contains [ByteRangeDTO])
    /// streamHealthChanged(_:)     — arg 0: StreamHealthDTO
    /// diskPressureChanged(_:)     — arg 0: DiskPressureDTO
    /// playbackHistoryChanged(_:)  — arg 0: PlaybackHistoryDTO (contains NSNumber? for completedAt)
    public static func eventsInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: EngineEvents.self)

        // torrentUpdated(_:) — arg 0: TorrentSummaryDTO
        interface.setClasses(
            [h(TorrentSummaryDTO.self)],
            for: #selector(EngineEvents.torrentUpdated(_:)),
            argumentIndex: 0,
            ofReply: false
        )

        // fileAvailabilityChanged(_:) — arg 0: FileAvailabilityDTO
        // FileAvailabilityDTO contains [ByteRangeDTO], so ByteRangeDTO must also be registered.
        interface.setClasses(
            [h(FileAvailabilityDTO.self), h(NSArray.self), h(ByteRangeDTO.self)],
            for: #selector(EngineEvents.fileAvailabilityChanged(_:)),
            argumentIndex: 0,
            ofReply: false
        )

        // streamHealthChanged(_:) — arg 0: StreamHealthDTO
        // NSNumber is included because StreamHealthDTO.requiredBitrateBytesPerSec is NSNumber?.
        interface.setClasses(
            [h(StreamHealthDTO.self), h(NSNumber.self)],
            for: #selector(EngineEvents.streamHealthChanged(_:)),
            argumentIndex: 0,
            ofReply: false
        )

        // diskPressureChanged(_:) — arg 0: DiskPressureDTO
        interface.setClasses(
            [h(DiskPressureDTO.self)],
            for: #selector(EngineEvents.diskPressureChanged(_:)),
            argumentIndex: 0,
            ofReply: false
        )

        // playbackHistoryChanged(_:) — arg 0: PlaybackHistoryDTO
        // PlaybackHistoryDTO carries an NSNumber? for completedAt.
        interface.setClasses(
            [h(PlaybackHistoryDTO.self), h(NSNumber.self)],
            for: #selector(EngineEvents.playbackHistoryChanged(_:)),
            argumentIndex: 0,
            ofReply: false
        )

        return interface
    }
}
