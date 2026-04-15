// Self-tests for HTTPParser, HTTPSerializer, and HTTPRangeResponse factories.
// Activated when the EngineService process is launched with the argument
//   --http-self-test
// Exits 0 on pass, 1 on failure.

#if DEBUG

import Foundation

/// Runs all HTTP gateway self-tests. Returns a list of failure messages.
/// An empty array means all tests passed.
func runHTTPSelfTests() -> [String] {
    var failures: [String] = []

    func fail(_ message: String, line: Int = #line) {
        failures.append("\(message) (line \(line))")
    }
    func expect(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition { fail(message, line: line) }
    }

    // MARK: - 1. Valid GET with Range

    do {
        let raw = "GET /stream/abc123 HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-1023\r\n\r\n"
        let data = raw.data(using: .utf8)!
        if let req = try HTTPParser.parse(data) {
            expect(req.method == .get, "method should be GET")
            expect(req.path == "/stream/abc123", "path should be /stream/abc123, got \(req.path)")
            expect(req.rangeStart == 0, "rangeStart should be 0, got \(String(describing: req.rangeStart))")
            expect(req.rangeEnd == 1023, "rangeEnd should be 1023, got \(String(describing: req.rangeEnd))")
        } else {
            fail("Expected a parsed request, got nil")
        }
    } catch {
        fail("Test 1 threw: \(error)")
    }

    // MARK: - 2. Valid HEAD without Range

    do {
        let raw = "HEAD /stream/xyz HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = raw.data(using: .utf8)!
        if let req = try HTTPParser.parse(data) {
            expect(req.method == .head, "method should be HEAD")
            expect(req.path == "/stream/xyz", "path should be /stream/xyz")
            expect(req.rangeStart == nil, "rangeStart should be nil")
            expect(req.rangeEnd == nil, "rangeEnd should be nil")
        } else {
            fail("Expected a parsed request, got nil")
        }
    } catch {
        fail("Test 2 threw: \(error)")
    }

    // MARK: - 3. Open-ended range (bytes=100-)

    do {
        let raw = "GET /stream/test HTTP/1.1\r\nRange: bytes=100-\r\n\r\n"
        let data = raw.data(using: .utf8)!
        if let req = try HTTPParser.parse(data) {
            expect(req.rangeStart == 100, "rangeStart should be 100, got \(String(describing: req.rangeStart))")
            expect(req.rangeEnd == nil, "rangeEnd should be nil for open-ended range")
        } else {
            fail("Expected a parsed request, got nil")
        }
    } catch {
        fail("Test 3 threw: \(error)")
    }

    // MARK: - 4. Malformed range — non-numeric start

    do {
        let raw = "GET /stream/test HTTP/1.1\r\nRange: bytes=abc-\r\n\r\n"
        let data = raw.data(using: .utf8)!
        _ = try HTTPParser.parse(data)
        fail("Test 4: should have thrown malformedRange, but did not")
    } catch HTTPParseError.malformedRange {
        // expected
    } catch {
        fail("Test 4: expected malformedRange, got \(error)")
    }

    // MARK: - 5. 416 response serialises correctly

    do {
        let response = HTTPRangeResponse.rangeNotSatisfiable(totalLength: 5000)
        let data = HTTPSerializer.serialize(response)
        let str = String(data: data, encoding: .utf8) ?? ""
        expect(str.hasPrefix("HTTP/1.1 416 Range Not Satisfiable\r\n"), "416 status line incorrect")
        expect(str.contains("Content-Range: bytes */5000\r\n"), "416 should include Content-Range with total length")
        expect(str.contains("Connection: close\r\n"), "416 should include Connection: close")
        // 416 has no body.
        let body = response.body
        expect(body == nil, "416 body should be nil")
    }

    // MARK: - 6. Incomplete request returns nil

    do {
        let raw = "GET /stream/test HTTP/1.1\r\nHost: localhost\r\n"  // No \r\n\r\n
        let data = raw.data(using: .utf8)!
        let result = try HTTPParser.parse(data)
        expect(result == nil, "Incomplete request should return nil, got \(String(describing: result))")
    } catch {
        fail("Test 6 threw: \(error)")
    }

    // MARK: - 7. Unsupported method (POST)

    do {
        let raw = "POST /stream/test HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = raw.data(using: .utf8)!
        _ = try HTTPParser.parse(data)
        fail("Test 7: should have thrown unsupportedMethod, but did not")
    } catch HTTPParseError.unsupportedMethod(let m) {
        expect(m == "POST", "unsupportedMethod should carry 'POST', got '\(m)'")
    } catch {
        fail("Test 7: expected unsupportedMethod, got \(error)")
    }

    // MARK: - 8a. 200 response serialises correctly

    do {
        let body = "hello".data(using: .utf8)!
        let response = HTTPRangeResponse.ok(contentType: "video/mp4", contentLength: 5, body: body)
        let data = HTTPSerializer.serialize(response)
        let str = String(data: data, encoding: .utf8) ?? ""
        expect(str.hasPrefix("HTTP/1.1 200 OK\r\n"), "200 status line incorrect")
        expect(str.contains("Content-Length: 5\r\n"), "200 should have Content-Length")
        expect(str.contains("Content-Type: video/mp4\r\n"), "200 should have Content-Type")
        expect(str.hasSuffix("hello"), "200 body should be appended after headers")
    }

    // MARK: - 8b. 206 response serialises correctly

    do {
        let body = Data(repeating: 0xAB, count: 10)
        let response = HTTPRangeResponse.partialContent(
            contentType: "video/mp4",
            rangeStart: 100,
            rangeEnd: 109,
            totalLength: 1000,
            body: body
        )
        let data = HTTPSerializer.serialize(response)
        let str = String(data: data, encoding: .utf8) ?? ""
        expect(str.hasPrefix("HTTP/1.1 206 Partial Content\r\n"), "206 status line incorrect")
        expect(str.contains("Content-Range: bytes 100-109/1000\r\n"), "206 Content-Range incorrect")
        expect(str.contains("Content-Length: 10\r\n"), "206 Content-Length should be range length")
    }

    // MARK: - 9. HEAD response has no body

    do {
        let response = HTTPRangeResponse.headResponse(contentType: "video/mp4", contentLength: 99999)
        let data = HTTPSerializer.serialize(response)
        let str = String(data: data, encoding: .utf8) ?? ""
        expect(str.hasPrefix("HTTP/1.1 200 OK\r\n"), "HEAD 200 status line incorrect")
        expect(str.contains("Content-Length: 99999\r\n"), "HEAD should carry Content-Length")
        // Body must be nil and not appended to the wire bytes.
        expect(response.body == nil, "HEAD response body should be nil")
        let headerEnd = str.range(of: "\r\n\r\n")
        let bodyPart = headerEnd.map { String(str[$0.upperBound...]) } ?? ""
        expect(bodyPart.isEmpty, "HEAD wire bytes should have no body after header block")
    }

    // MARK: - 10. Header keys are lowercased during parse

    do {
        let raw = "GET /stream/test HTTP/1.1\r\nX-Custom-Header: SomeValue\r\nRange: bytes=0-99\r\n\r\n"
        let data = raw.data(using: .utf8)!
        if let req = try HTTPParser.parse(data) {
            expect(req.headers["x-custom-header"] == "SomeValue",
                   "header keys should be lowercased; got \(req.headers)")
        } else {
            fail("Test 10: expected parsed request, got nil")
        }
    } catch {
        fail("Test 10 threw: \(error)")
    }

    // MARK: - 11. Range with end < start is malformed

    do {
        let (_, _) = try HTTPParser.parseRange("bytes=500-100")
        fail("Test 11: end < start should throw malformedRange")
    } catch HTTPParseError.malformedRange {
        // expected
    } catch {
        fail("Test 11: expected malformedRange, got \(error)")
    }

    return failures
}

/// Entry point called from main.swift when --http-self-test is passed.
func runHTTPSelfTestAndExit() {
    let failures = runHTTPSelfTests()
    if failures.isEmpty {
        NSLog("[HTTPSelfTest] All tests passed.")
        exit(0)
    } else {
        NSLog("[HTTPSelfTest] FAILED — %d failure(s):", failures.count)
        for f in failures {
            NSLog("[HTTPSelfTest]   FAIL: %@", f)
        }
        exit(1)
    }
}

#endif // DEBUG
