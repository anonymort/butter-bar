import Foundation

struct HTTPSerializer {

    /// Serialise an `HTTPRangeResponse` to wire bytes.
    ///
    /// Headers are emitted in ascending key order for determinism.
    /// The body (if any) is appended after the blank line.
    static func serialize(_ response: HTTPRangeResponse) -> Data {
        var header = "HTTP/1.1 \(response.statusCode) \(response.statusText)\r\n"
        for (key, value) in response.headers.sorted(by: { $0.key < $1.key }) {
            header += "\(key): \(value)\r\n"
        }
        header += "\r\n"

        var data = header.data(using: .utf8)!
        if let body = response.body {
            data.append(body)
        }
        return data
    }
}
