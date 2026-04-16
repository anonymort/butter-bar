// EngineService XPC service entry point.
//
// Uses @main pattern instead of main.swift top-level code. The XPC runtime
// launches Swift services via the @main attribute's entry point; top-level
// statements in main.swift are NOT executed when the binary is XPC-brokered
// (they run only on direct invocation). This was observed 2026-04-16 and
// manifested as "Could not load library: EngineClientError error 1" — the
// backend was never constructed so no XPC method could be routed.
//
// Pass `--bridge-self-test`, `--cache-eviction-probe`, `--stream-e2e-self-test`,
// etc. as launch arguments to run self-tests and exit (DEBUG builds only).

import Foundation
import EngineInterface

// MARK: - XPCDelegate

/// Owns the shared backend for the process lifetime.
/// All per-connection `EngineXPCServer` instances delegate to this single backend.
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

// MARK: - @main entry

@main
enum EngineServiceMain {
    static func main() {
        NSLog("[EngineService-main] process starting, args=%@", CommandLine.arguments as NSArray)

        #if DEBUG
        if let probeIdx = CommandLine.arguments.firstIndex(of: "--cache-eviction-probe") {
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

        NSLog("[EngineService-main] creating XPCDelegate + backend")
        let delegate = XPCDelegate()
        NSLog("[EngineService-main] delegate ready, backend=%@", String(describing: type(of: delegate.backend)))

        let listener = NSXPCListener.service()
        listener.delegate = delegate
        NSLog("[EngineService-main] starting NSXPCListener.service()")
        listener.resume()
        // resume() blocks forever on a valid XPC context, keeping `delegate`
        // alive on the stack. If it ever returns, something is wrong.
        NSLog("[EngineService-main] listener.resume() returned unexpectedly — exiting")
        // Retain via dispatchMain so the process doesn't immediately die if
        // resume() returned because the context wasn't XPC (e.g. direct launch).
        withExtendedLifetime(delegate) {
            dispatchMain()
        }
    }
}
