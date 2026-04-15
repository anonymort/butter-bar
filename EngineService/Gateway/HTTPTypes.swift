import Foundation

/// Parsed HTTP request relevant to the gateway.
struct HTTPRangeRequest {
    enum Method: String {
        case head = "HEAD"
        case get = "GET"
    }

    let method: Method
    /// URL path, e.g. "/stream/<streamID>"
    let path: String
    /// Byte offset from Range: bytes=START-END; nil if no Range header.
    let rangeStart: Int64?
    /// Inclusive end byte offset; nil means "to end of file".
    let rangeEnd: Int64?
    /// All request headers, keys lowercased.
    let headers: [String: String]
}

/// HTTP response to send back to the client.
struct HTTPRangeResponse {
    let statusCode: Int
    let statusText: String
    /// Response headers (will be serialized in sorted order for determinism).
    let headers: [String: String]
    /// Nil for HEAD responses and responses with no body (e.g. 416).
    let body: Data?

    static func ok(contentType: String, contentLength: Int64, body: Data) -> HTTPRangeResponse {
        HTTPRangeResponse(
            statusCode: 200,
            statusText: "OK",
            headers: [
                "Accept-Ranges": "bytes",
                "Connection": "close",
                "Content-Length": "\(contentLength)",
                "Content-Type": contentType,
            ],
            body: body
        )
    }

    static func partialContent(
        contentType: String,
        rangeStart: Int64,
        rangeEnd: Int64,
        totalLength: Int64,
        body: Data
    ) -> HTTPRangeResponse {
        HTTPRangeResponse(
            statusCode: 206,
            statusText: "Partial Content",
            headers: [
                "Accept-Ranges": "bytes",
                "Connection": "close",
                "Content-Length": "\(rangeEnd - rangeStart + 1)",
                "Content-Range": "bytes \(rangeStart)-\(rangeEnd)/\(totalLength)",
                "Content-Type": contentType,
            ],
            body: body
        )
    }

    static func rangeNotSatisfiable(totalLength: Int64) -> HTTPRangeResponse {
        HTTPRangeResponse(
            statusCode: 416,
            statusText: "Range Not Satisfiable",
            headers: [
                "Connection": "close",
                "Content-Range": "bytes */\(totalLength)",
            ],
            body: nil
        )
    }

    static func headResponse(contentType: String, contentLength: Int64) -> HTTPRangeResponse {
        HTTPRangeResponse(
            statusCode: 200,
            statusText: "OK",
            headers: [
                "Accept-Ranges": "bytes",
                "Connection": "close",
                "Content-Length": "\(contentLength)",
                "Content-Type": contentType,
            ],
            body: nil
        )
    }

    static func notFound() -> HTTPRangeResponse {
        HTTPRangeResponse(
            statusCode: 404,
            statusText: "Not Found",
            headers: [
                "Connection": "close",
                "Content-Length": "0",
            ],
            body: nil
        )
    }
}
