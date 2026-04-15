// EngineService XPC service entry point.
// Sets up NSXPCListener and exports EngineXPCServer on every incoming connection.
import Foundation
import EngineInterface

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
