// EngineService XPC service entry point.
// Sets up NSXPCListener and exports EngineXPCServer on every incoming connection.
//
// Pass --bridge-self-test as a launch argument (DEBUG builds only) to run
// TorrentBridge self-tests and exit with 0/1.
import Foundation
import EngineInterface

#if DEBUG
if let probeIdx = CommandLine.arguments.firstIndex(of: "--cache-eviction-probe") {
    // Pass everything after the flag so the probe can parse <magnet-or-path> and --file-index N.
    let trailingArgs = Array(CommandLine.arguments.dropFirst(probeIdx + 1))
    runCacheEvictionProbeAndExit(trailingArgs: trailingArgs)
}
if CommandLine.arguments.contains("--bridge-self-test") {
    runBridgeSelfTestAndExit()
}
if CommandLine.arguments.contains("--http-self-test") {
    runHTTPSelfTestAndExit()
}
if CommandLine.arguments.contains("--gateway-planner-self-test") {
    runGatewayPlannerSelfTestAndExit()
}
if let e2eIdx = CommandLine.arguments.firstIndex(of: "--stream-e2e-self-test") {
    let trailingArgs = Array(CommandLine.arguments.dropFirst(e2eIdx + 1))
    runStreamE2ESelfTestAndExit(trailingArgs: trailingArgs)
}
if CommandLine.arguments.contains("--cache-manager-self-test") {
    runCacheManagerSelfTestAndExit()
}
if CommandLine.arguments.contains("--resume-tracker-self-test") {
    runResumeTrackerSelfTestAndExit()
}
#endif

// XPCDelegate owns the shared backend for the process lifetime.
// All per-connection EngineXPCServer instances delegate to this single instance.
// The backend is stored on the delegate (not as a top-level let) to avoid Swift 6
// main-actor isolation issues with top-level stored properties.
final class XPCDelegate: NSObject, NSXPCListenerDelegate {
    let backend: any EngineXPCBackend

    override init() {
        if CommandLine.arguments.contains("--fake-backend") {
            backend = FakeEngineBackend()
        } else {
            backend = RealEngineBackend()
        }
        super.init()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = XPCInterfaceFactory.engineInterface()
        connection.exportedObject = EngineXPCServer(backend: backend)

        // Log connection lifecycle events; do not crash on either.
        connection.invalidationHandler = {
            NSLog("[EngineService] XPC connection invalidated")
        }
        connection.interruptionHandler = {
            NSLog("[EngineService] XPC connection interrupted — client may reconnect")
        }

        connection.resume()
        return true
    }
}

let delegate = XPCDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume() // Never returns; RunLoop kept alive by XPC infrastructure.
