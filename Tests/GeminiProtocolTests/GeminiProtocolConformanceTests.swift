//
// GeminiProtocolConformanceTests.swift
//
// Copyright © 2022 Izzy Fraimow. All rights reserved.
//

import Foundation
import XCTest
@testable import GeminiProtocol

final class GeminiProtocolConformanceTests: XCTestCase {
    private let server = GeminiTestServer()
    
    override func setUp() async throws {
        GeminiProtocol.usePlaintextTransport = true
    }
    
    override func tearDown() async throws {
        await server.stop()
        GeminiProtocol.usePlaintextTransport = false
    }
    
    func testRequestOmitsFragmentAndNormalizesEmptyPath() async throws {
        let port = try await server.start(
            header: GeminiResponseHeader(status: .success, meta: "text/plain"),
            body: "ok"
        )
        let url = URL(string: "gemini://127.0.0.1:\(port)?q=test#local-fragment")!
        let client = try GeminiClient(request: URLRequest(url: url), debug: true)
        _ = try await client.start()
        
        let observedLine = await server.observedRequestLine()
        let requestLine = try XCTUnwrap(observedLine)
        XCTAssertEqual(requestLine, "gemini://127.0.0.1:\(port)/?q=test")
        XCTAssertFalse(requestLine.contains("#"))
    }
    
    func testRequestRejectsUserInfo() throws {
        let url = URL(string: "gemini://user:pass@example.com/")!
        XCTAssertThrowsError(try GeminiClient(request: URLRequest(url: url), debug: true))
    }
    
    func testRequestRejectsURIOver1024Bytes() {
        let largeQuery = String(repeating: "a", count: 1100)
        let url = URL(string: "gemini://example.com/?q=\(largeQuery)")!
        XCTAssertThrowsError(try GeminiClient(request: URLRequest(url: url), debug: true))
    }
    
    func testParsesPermanentFailureWithoutMeta() async throws {
        let port = try await server.start(rawResponse: Data("50\r\n".utf8))
        let url = URL(string: "gemini://127.0.0.1:\(port)/")!
        let client = try GeminiClient(request: URLRequest(url: url), debug: true)
        let (header, body) = try await client.start()
        
        XCTAssertEqual(header.status, .permanentFailure)
        XCTAssertEqual(header.meta, "")
        XCTAssertNil(body)
    }
    
    func testRejectsFailureHeaderWithSpaceButNoErrorMessage() async throws {
        let port = try await server.start(rawResponse: Data("50 \r\n".utf8))
        let url = URL(string: "gemini://127.0.0.1:\(port)/")!
        let client = try GeminiClient(request: URLRequest(url: url), debug: true)
        
        await XCTAssertThrowsErrorAsync {
            _ = try await client.start()
        }
    }
    
    func testRejectsSuccessHeaderWithoutRequiredMeta() async throws {
        let payload = Data("20\r\nHello".utf8)
        let port = try await server.start(rawResponse: payload)
        let url = URL(string: "gemini://127.0.0.1:\(port)/")!
        let client = try GeminiClient(request: URLRequest(url: url), debug: true)
        
        await XCTAssertThrowsErrorAsync {
            _ = try await client.start()
        }
    }
    
    func testRejectsHeaderWithLeadingUtf8BOM() async throws {
        var payload = Data([0xEF, 0xBB, 0xBF])
        payload.append(Data("20 text/plain\r\nHello".utf8))
        
        let port = try await server.start(rawResponse: payload)
        let url = URL(string: "gemini://127.0.0.1:\(port)/")!
        let client = try GeminiClient(request: URLRequest(url: url), debug: true)
        
        await XCTAssertThrowsErrorAsync {
            _ = try await client.start()
        }
    }
    
    func testHandlesUndefinedSuccessStatusWithinValidRange() async throws {
        let payload = Data("21 text/plain\r\nHello".utf8)
        let port = try await server.start(rawResponse: payload)
        let url = URL(string: "gemini://127.0.0.1:\(port)/")!
        let client = try GeminiClient(request: URLRequest(url: url), debug: true)
        let (header, body) = try await client.start()
        
        XCTAssertEqual(header.status, .success)
        let data = try XCTUnwrap(body)
        XCTAssertEqual(String(data: data, encoding: .utf8), "Hello")
    }
    
    func testRejectsOutOfRangeStatusCode() async throws {
        let payload = Data("70 invalid\r\n".utf8)
        let port = try await server.start(rawResponse: payload)
        let url = URL(string: "gemini://127.0.0.1:\(port)/")!
        let client = try GeminiClient(request: URLRequest(url: url), debug: true)
        
        await XCTAssertThrowsErrorAsync {
            _ = try await client.start()
        }
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        // Expected error.
    }
}
