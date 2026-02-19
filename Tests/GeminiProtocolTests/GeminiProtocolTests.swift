//
// GeminiProtocolTests.swift
//
// Copyright © 2022 Izzy Fraimow. All rights reserved.
//

import XCTest
@testable import GeminiProtocol

enum GeminiHeaders {
    static let successWithGeminiContent = GeminiResponseHeader(status: .success, meta: "text/gemini")
}

enum GeminiBodies {
    static let genericBody = """
        # Gemini
        
        This is a response body
        
        ## Title 2
        
        
        """
}

final class GeminiProtocolTests: XCTestCase {
    let server = GeminiTestServer()
    
    override class func setUp() {
        setenv("CFNETWORK_DIAGNOSTICS", "3", 1)
    }

    override func setUp() async throws {
        GeminiProtocol.usePlaintextTransport = true
        URLProtocol.registerClass(GeminiProtocol.self)
    }
    
    override func tearDown() async throws {
        await server.stop()
        GeminiProtocol.usePlaintextTransport = false
        URLProtocol.unregisterClass(GeminiProtocol.self)
    }
    
    func testRequest() async throws {
        let port = try await server.start(header: GeminiHeaders.successWithGeminiContent, body: GeminiBodies.genericBody)

        let url = URL(string: "gemini://127.0.0.1:\(port)")!
        let client = try GeminiClient(request: URLRequest(url: url), debug: true)
        let (header, maybeData) = try await client.start()
        
        XCTAssertEqual(header, GeminiHeaders.successWithGeminiContent)
        
        let data = try XCTUnwrap(maybeData)
        let string = try XCTUnwrap(String(data: data, encoding: .utf8))
        
        XCTAssertEqual(string, GeminiBodies.genericBody)
    }
    
    func testURLSessionProtocolIntegration() async throws {
        let port = try await server.start(header: GeminiHeaders.successWithGeminiContent, body: GeminiBodies.genericBody)
        
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiProtocol.self]
        let session = URLSession(configuration: configuration)
        
        let url = URL(string: "gemini://127.0.0.1:\(port)")!
        let (data, response) = try await session.data(from: url)
        
        if let geminiResponse = response as? GeminiURLResponse {
            XCTAssertEqual(geminiResponse.statusCode, .success)
            XCTAssertEqual(geminiResponse.meta, "text/gemini")
        } else {
            XCTAssertEqual(response.mimeType, "text/gemini")
        }
        
        let body = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(body, GeminiBodies.genericBody)
    }
}
