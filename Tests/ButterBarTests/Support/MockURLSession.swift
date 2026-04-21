import Foundation

/// Lightweight URLSession stub for unit tests. Registers a `URLProtocol` subclass
/// that returns the given data for every request without hitting the network.
extension URLSession {
    static func mockSession(data: Data, statusCode: Int = 200) -> URLSession {
        MockURLProtocol.responseData = data
        MockURLProtocol.responseStatusCode = statusCode

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class MockURLProtocol: URLProtocol {
    // Test-thread written, protocol-thread read — simple nonisolated storage is
    // fine for the sequential unit-test use case.
    static var responseData: Data = Data()
    static var responseStatusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "about:blank")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: MockURLProtocol.responseStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: MockURLProtocol.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
