// EngineService XPC service entry point.
// Sets up NSXPCListener and exports EngineXPCServer on every incoming connection.
//
// Pass --bridge-self-test as a launch argument (DEBUG builds only) to run
// TorrentBridge self-tests and exit with 0/1.
import Foundation
import EngineInterface

#if DEBUG
if CommandLine.arguments.contains("--bridge-self-test") {
    runBridgeSelfTestAndExit()
}
if CommandLine.arguments.contains("--http-self-test") {
    runHTTPSelfTestAndExit()
}
if CommandLine.arguments.contains("--gateway-planner-self-test") {
    runGatewayPlannerSelfTestAndExit()
}
if CommandLine.arguments.contains("--stream-e2e-self-test") {
    runStreamE2ESelfTestAndExit()
}
#endif

final class XPCDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = XPCInterfaceFactory.engineInterface()
        connection.exportedObject = EngineXPCServer()

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
