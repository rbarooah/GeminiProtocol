//
// LiveGeminiSitesTests.swift
//
// Copyright © 2022 Izzy Fraimow. All rights reserved.
//

import Foundation
import XCTest
@testable import GeminiProtocol

final class LiveGeminiSitesTests: XCTestCase {
    private struct LiveTarget {
        let url: URL
        let tlsMode: GeminiTLSMode
    }
    
    private let liveCapsules: [LiveTarget] = [
        LiveTarget(url: URL(string: "gemini://gemini.bortzmeyer.org/")!, tlsMode: .systemTrust),
        LiveTarget(url: URL(string: "gemini://gemini.circumlunar.space/")!, tlsMode: .insecureNoVerification),
        LiveTarget(url: URL(string: "gemini://geminiprotocol.net/")!, tlsMode: .insecureNoVerification),
        LiveTarget(url: URL(string: "gemini://kennedy.gemi.dev/")!, tlsMode: .insecureNoVerification)
    ]
    
    func testFetchesMultiplePublicGeminiCapsules() async throws {
        guard ProcessInfo.processInfo.environment["GEMINI_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set GEMINI_LIVE_TESTS=1 to run live Gemini capsule tests.")
        }
        
        var successes: [String] = []
        var failures: [String] = []
        
        for target in liveCapsules {
            do {
                let request = URLRequest(url: target.url)
                let client = try GeminiClient(request: request, tlsMode: target.tlsMode)
                let (header, maybeData) = try await client.start(timeout: 20)
                
                if header.status.isSuccess, let data = maybeData, data.isEmpty {
                    failures.append("\(target.url.absoluteString): success response had an empty body")
                    continue
                }
                
                successes.append("\(target.url.absoluteString): \(header.status.rawValue)")
            } catch {
                failures.append("\(target.url.absoluteString): \(error.localizedDescription)")
            }
        }
        
        XCTAssertGreaterThanOrEqual(
            successes.count,
            3,
            """
            Expected at least 3 live capsules to respond successfully.
            Successes: \(successes)
            Failures: \(failures)
            """
        )
    }
}
