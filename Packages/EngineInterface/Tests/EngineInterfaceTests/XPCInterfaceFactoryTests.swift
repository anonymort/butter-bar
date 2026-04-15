import XCTest
@testable import EngineInterface

/// Tests that XPCInterfaceFactory registers allowed classes for every method on both protocols.
///
/// Missing class registrations are silent failures at XPC runtime — this test suite is the
/// primary defence against that class of bug.
final class XPCInterfaceFactoryTests: XCTestCase {

    // MARK: - Helpers

    /// Boxes an ObjC class metatype to AnyHashable for use with Set.contains.
    private func h(_ cls: AnyClass) -> AnyHashable {
        cls as AnyObject as! AnyHashable
    }

    // MARK: - EngineXPC interface

    func testEngineInterface_addMagnet_replyArg0_containsTorrentSummaryDTO() {
        let iface = XPCInterfaceFactory.engineInterface()
        let classes = iface.classes(
            for: #selector(EngineXPC.addMagnet(_:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        XCTAssertTrue(classes.contains(h(TorrentSummaryDTO.self)),
                      "addMagnet reply arg 0 must include TorrentSummaryDTO")
    }

    func testEngineInterface_addTorrentFile_replyArg0_containsTorrentSummaryDTO() {
        let iface = XPCInterfaceFactory.engineInterface()
        let classes = iface.classes(
            for: #selector(EngineXPC.addTorrentFile(_:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        XCTAssertTrue(classes.contains(h(TorrentSummaryDTO.self)),
                      "addTorrentFile reply arg 0 must include TorrentSummaryDTO")
    }

    func testEngineInterface_listTorrents_replyArg0_containsArrayAndDTO() {
        let iface = XPCInterfaceFactory.engineInterface()
        let classes = iface.classes(
            for: #selector(EngineXPC.listTorrents(_:)),
            argumentIndex: 0,
            ofReply: true
        )
        XCTAssertTrue(classes.contains(h(NSArray.self)),
                      "listTorrents reply must include NSArray")
        XCTAssertTrue(classes.contains(h(TorrentSummaryDTO.self)),
                      "listTorrents reply must include TorrentSummaryDTO")
    }

    func testEngineInterface_listFiles_replyArg0_containsArrayAndDTO() {
        let iface = XPCInterfaceFactory.engineInterface()
        let classes = iface.classes(
            for: #selector(EngineXPC.listFiles(_:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        XCTAssertTrue(classes.contains(h(NSArray.self)),
                      "listFiles reply must include NSArray")
        XCTAssertTrue(classes.contains(h(TorrentFileDTO.self)),
                      "listFiles reply must include TorrentFileDTO")
    }

    func testEngineInterface_setWantedFiles_arg1_containsArrayAndNSNumber() {
        let iface = XPCInterfaceFactory.engineInterface()
        let classes = iface.classes(
            for: #selector(EngineXPC.setWantedFiles(_:fileIndexes:reply:)),
            argumentIndex: 1,
            ofReply: false
        )
        XCTAssertTrue(classes.contains(h(NSArray.self)),
                      "setWantedFiles fileIndexes must include NSArray")
        XCTAssertTrue(classes.contains(h(NSNumber.self)),
                      "setWantedFiles fileIndexes must include NSNumber")
    }

    func testEngineInterface_openStream_replyArg0_containsStreamDescriptorDTO() {
        let iface = XPCInterfaceFactory.engineInterface()
        let classes = iface.classes(
            for: #selector(EngineXPC.openStream(_:fileIndex:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        XCTAssertTrue(classes.contains(h(StreamDescriptorDTO.self)),
                      "openStream reply must include StreamDescriptorDTO")
    }

    /// subscribe(_:reply:) uses setInterface rather than setClasses.
    /// Verify the nested events interface is set by checking it's non-nil for arg 0.
    func testEngineInterface_subscribe_arg0_hasEventsInterface() {
        let iface = XPCInterfaceFactory.engineInterface()
        let nested = iface.forSelector(
            #selector(EngineXPC.subscribe(_:reply:)),
            argumentIndex: 0,
            ofReply: false
        )
        XCTAssertNotNil(nested,
                        "subscribe arg 0 must have an NSXPCInterface set for EngineEvents")
    }

    // MARK: - EngineEvents interface

    func testEventsInterface_torrentUpdated_arg0_containsTorrentSummaryDTO() {
        let iface = XPCInterfaceFactory.eventsInterface()
        let classes = iface.classes(
            for: #selector(EngineEvents.torrentUpdated(_:)),
            argumentIndex: 0,
            ofReply: false
        )
        XCTAssertTrue(classes.contains(h(TorrentSummaryDTO.self)),
                      "torrentUpdated arg 0 must include TorrentSummaryDTO")
    }

    func testEventsInterface_fileAvailabilityChanged_arg0_containsAllRequired() {
        let iface = XPCInterfaceFactory.eventsInterface()
        let classes = iface.classes(
            for: #selector(EngineEvents.fileAvailabilityChanged(_:)),
            argumentIndex: 0,
            ofReply: false
        )
        XCTAssertTrue(classes.contains(h(FileAvailabilityDTO.self)),
                      "fileAvailabilityChanged must include FileAvailabilityDTO")
        // ByteRangeDTO is nested inside FileAvailabilityDTO.availableRanges — it must be registered
        // or XPC will refuse to decode the array elements.
        XCTAssertTrue(classes.contains(h(ByteRangeDTO.self)),
                      "fileAvailabilityChanged must include ByteRangeDTO (nested in availableRanges)")
        XCTAssertTrue(classes.contains(h(NSArray.self)),
                      "fileAvailabilityChanged must include NSArray (for the ranges array)")
    }

    func testEventsInterface_streamHealthChanged_arg0_containsStreamHealthDTO() {
        let iface = XPCInterfaceFactory.eventsInterface()
        let classes = iface.classes(
            for: #selector(EngineEvents.streamHealthChanged(_:)),
            argumentIndex: 0,
            ofReply: false
        )
        XCTAssertTrue(classes.contains(h(StreamHealthDTO.self)),
                      "streamHealthChanged arg 0 must include StreamHealthDTO")
    }

    func testEventsInterface_diskPressureChanged_arg0_containsDiskPressureDTO() {
        let iface = XPCInterfaceFactory.eventsInterface()
        let classes = iface.classes(
            for: #selector(EngineEvents.diskPressureChanged(_:)),
            argumentIndex: 0,
            ofReply: false
        )
        XCTAssertTrue(classes.contains(h(DiskPressureDTO.self)),
                      "diskPressureChanged arg 0 must include DiskPressureDTO")
    }

    // MARK: - Completeness guards

    /// Verifies that all EngineXPC methods with DTO reply types have their custom class
    /// registered. An absent registration means XPC silently drops the decoded object.
    func testEngineInterface_allDTOCarryingRepliesHaveCustomClasses() {
        let iface = XPCInterfaceFactory.engineInterface()

        // (selector, argIndex, isReply, expectedClass, label)
        let cases: [(sel: Selector, argIdx: Int, isReply: Bool, cls: AnyClass, label: String)] = [
            (#selector(EngineXPC.addMagnet(_:reply:)),            0, true,  TorrentSummaryDTO.self,  "addMagnet reply"),
            (#selector(EngineXPC.addTorrentFile(_:reply:)),       0, true,  TorrentSummaryDTO.self,  "addTorrentFile reply"),
            (#selector(EngineXPC.listTorrents(_:)),               0, true,  TorrentSummaryDTO.self,  "listTorrents reply"),
            (#selector(EngineXPC.listFiles(_:reply:)),            0, true,  TorrentFileDTO.self,     "listFiles reply"),
            (#selector(EngineXPC.openStream(_:fileIndex:reply:)), 0, true,  StreamDescriptorDTO.self,"openStream reply"),
        ]

        for c in cases {
            let classes = iface.classes(for: c.sel, argumentIndex: c.argIdx, ofReply: c.isReply)
            XCTAssertTrue(classes.contains(h(c.cls)),
                          "\(c.label): missing registration for \(c.cls) — silent decode failure at runtime")
        }
    }

    /// Verifies that all EngineEvents methods have their DTO class registered.
    func testEventsInterface_allMethodsHaveTheirDTORegistered() {
        let iface = XPCInterfaceFactory.eventsInterface()

        let cases: [(sel: Selector, cls: AnyClass, label: String)] = [
            (#selector(EngineEvents.torrentUpdated(_:)),          TorrentSummaryDTO.self,   "torrentUpdated"),
            (#selector(EngineEvents.fileAvailabilityChanged(_:)), FileAvailabilityDTO.self, "fileAvailabilityChanged"),
            (#selector(EngineEvents.streamHealthChanged(_:)),     StreamHealthDTO.self,     "streamHealthChanged"),
            (#selector(EngineEvents.diskPressureChanged(_:)),     DiskPressureDTO.self,     "diskPressureChanged"),
        ]

        for c in cases {
            let classes = iface.classes(for: c.sel, argumentIndex: 0, ofReply: false)
            XCTAssertTrue(classes.contains(h(c.cls)),
                          "\(c.label): missing registration for \(c.cls) — silent decode failure at runtime")
        }
    }
}
