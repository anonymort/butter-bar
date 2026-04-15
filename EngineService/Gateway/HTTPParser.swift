import Foundation

enum HTTPParseError: Error {
    /// The request is incomplete — more data is needed.
    case incomplete
    /// The request line could not be parsed.
    case malformedRequestLine
    /// Method is syntactically valid but not supported (not HEAD/GET).
    case unsupportedMethod(String)
    /// The Range header value could not be parsed.
    case malformedRange(String)
}

struct HTTPParser {

    /// Parse raw HTTP/1.1 request bytes into an `HTTPRangeRequest`.
    ///
    /// Returns `nil` when the data does not yet contain a complete request header
    /// block (no `\r\n\r\n` terminator). Throws on malformed or unsupported input.
    static func parse(_ data: Data) throws -> HTTPRangeRequest? {
        guard let str = String(data: data, encoding: .utf8) else {
            throw HTTPParseError.malformedRequestLine
        }

        // A complete HTTP request header block ends with CRLFCRLF.
        guard str.contains("\r\n\r\n") else { return nil }

        // Only look at the header section (before the blank line).
        let headerSection = str.components(separatedBy: "\r\n\r\n")[0]
        let lines = headerSection.components(separatedBy: "\r\n")

        guard let requestLine = lines.first, !requestLine.isEmpty else {
            throw HTTPParseError.malformedRequestLine
        }

        // Parse "METHOD /path HTTP/1.1"
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            throw HTTPParseError.malformedRequestLine
        }

        let methodStr = String(parts[0])
        guard let method = HTTPRangeRequest.Method(rawValue: methodStr) else {
            throw HTTPParseError.unsupportedMethod(methodStr)
        }

        let path = String(parts[1])

        // Parse headers (key: value pairs after the request line).
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { break }
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIdx])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = String(line[line.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        // Parse Range header if present.
        var rangeStart: Int64?
        var rangeEnd: Int64?
        if let rangeHeader = headers["range"] {
            (rangeStart, rangeEnd) = try parseRange(rangeHeader)
        }

        return HTTPRangeRequest(
            method: method,
            path: path,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            headers: headers
        )
    }

    /// Parse an RFC 7233 byte-range specifier: `bytes=START-` or `bytes=START-END`.
    ///
    /// Returns `(start, end)` where `end` is `nil` for an open-ended range.
    /// Throws `malformedRange` for anything that doesn't conform.
    static func parseRange(_ header: String) throws -> (Int64?, Int64?) {
        let prefix = "bytes="
        guard header.lowercased().hasPrefix(prefix) else {
            throw HTTPParseError.malformedRange(header)
        }

        let rangeSpec = String(header.dropFirst(prefix.count))

        // Must contain exactly one dash to separate start and end.
        guard let dashIdx = rangeSpec.firstIndex(of: "-") else {
            throw HTTPParseError.malformedRange(header)
        }

        let startStr = String(rangeSpec[rangeSpec.startIndex..<dashIdx])
            .trimmingCharacters(in: .whitespaces)
        let endStr = String(rangeSpec[rangeSpec.index(after: dashIdx)...])
            .trimmingCharacters(in: .whitespaces)

        // Start must be a non-negative integer.
        guard !startStr.isEmpty, let start = Int64(startStr), start >= 0 else {
            throw HTTPParseError.malformedRange(header)
        }

        // End is optional (open-ended range); if present it must be >= start.
        if endStr.isEmpty {
            return (start, nil)
        }

        guard let end = Int64(endStr), end >= start else {
            throw HTTPParseError.malformedRange(header)
        }

        return (start, end)
    }
}
