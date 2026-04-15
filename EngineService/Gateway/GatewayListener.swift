import Foundation
import Network

/// Loopback HTTP listener for the playback gateway.
/// Binds to 127.0.0.1 on an ephemeral port. The actual port is
/// available via `port` once `stateUpdateHandler` reports `.ready`.
// @unchecked Sendable: internal state (port, onReady, requestHandler) is only
// mutated before `start()` is called, then read-only from the gateway queue.
final class GatewayListener: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.butterbar.engine.gateway")

    /// The port the listener is bound to, or nil if not yet ready.
    private(set) var port: UInt16?

    /// Called when the listener becomes ready (port is available).
    var onReady: ((UInt16) -> Void)?

    /// Optional handler for parsed requests. When nil, all requests receive 404.
    /// Set this before calling `start()`. Called on the gateway dispatch queue.
    var requestHandler: ((HTTPRangeRequest) -> HTTPRangeResponse)?

    init() throws {
        let params = NWParameters.tcp
        // Bind to loopback only — no external network exposure.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: .any
        )
        listener = try NWListener(using: params)
    }

    func start() {
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener.port?.rawValue {
                    self?.port = port
                    self?.onReady?(port)
                    NSLog("[GatewayListener] listening on 127.0.0.1:%d", port)
                }
            case .failed(let error):
                NSLog("[GatewayListener] failed: %@", error.localizedDescription)
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection: connection, buffer: Data())
    }

    /// Accumulate bytes until we have a complete HTTP request, then handle it.
    private func receiveRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let error = error {
                NSLog("[GatewayListener] receive error: %@", error.localizedDescription)
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let data = data, !data.isEmpty {
                accumulated.append(data)
            }

            do {
                if let request = try HTTPParser.parse(accumulated) {
                    self?.dispatch(request: request, over: connection)
                } else if isComplete {
                    // Connection closed before we got a full request.
                    connection.cancel()
                } else {
                    // Need more data — keep reading.
                    self?.receiveRequest(connection: connection, buffer: accumulated)
                }
            } catch let parseError as HTTPParseError {
                NSLog("[GatewayListener] parse error: %@", "\(parseError)")
                let response = HTTPRangeResponse.notFound()
                self?.send(response: response, over: connection)
            } catch {
                NSLog("[GatewayListener] unexpected error: %@", error.localizedDescription)
                connection.cancel()
            }
        }
    }

    private func dispatch(request: HTTPRangeRequest, over connection: NWConnection) {
        let response: HTTPRangeResponse
        if let handler = requestHandler {
            response = handler(request)
        } else {
            NSLog("[GatewayListener] no handler — returning 404 for %@", request.path)
            response = HTTPRangeResponse.notFound()
        }
        send(response: response, over: connection)
    }

    private func send(response: HTTPRangeResponse, over connection: NWConnection) {
        let data = HTTPSerializer.serialize(response)
        connection.send(content: data, isComplete: true, completion: .contentProcessed { error in
            if let error = error {
                NSLog("[GatewayListener] send error: %@", error.localizedDescription)
            }
            connection.cancel()
        })
    }
}
