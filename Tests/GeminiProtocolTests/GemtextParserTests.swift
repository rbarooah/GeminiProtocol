//
// GemtextParserTests.swift
//
// Copyright (c) 2022 Izzy Fraimow. All rights reserved.
//

import Foundation
import XCTest
@testable import GeminiProtocol

final class GemtextParserTests: XCTestCase {
    func testParsesFixtureWithDedicatedNodeTypes() throws {
        let source = try loadFixture(named: "sample")
        let baseURL = URL(string: "gemini://example.org/base/")!
        let document = try GemtextParser.parse(source, options: .init(baseURL: baseURL))
        
        XCTAssertEqual(document.lines.count, 10)
        XCTAssertTrue(document.diagnostics.isEmpty)
        
        guard case .heading(let heading) = document.lines[0] else {
            return XCTFail("Expected heading line")
        }
        XCTAssertEqual(heading.level, 1)
        XCTAssertEqual(heading.text, "Gemini Title")
        XCTAssertEqual(heading.raw, "# Gemini Title")
        
        guard case .link(let firstLink) = document.lines[2] else {
            return XCTFail("Expected first link line")
        }
        XCTAssertEqual(firstLink.target, "/docs/spec.gmi")
        XCTAssertEqual(firstLink.label, "Protocol specification")
        XCTAssertEqual(firstLink.resolvedURL?.absoluteString, "gemini://example.org/docs/spec.gmi")
        
        guard case .preformatToggle(let enterToggle) = document.lines[6] else {
            return XCTFail("Expected enter preformat toggle")
        }
        XCTAssertEqual(enterToggle.altText, "swift")
        XCTAssertTrue(enterToggle.entersPreformatted)
        
        guard case .text(let codeLine) = document.lines[7] else {
            return XCTFail("Expected preformatted text line")
        }
        XCTAssertTrue(codeLine.isPreformatted)
        XCTAssertEqual(codeLine.text, "let x = 1")
    }
    
    func testPermissiveModeCollectsDiagnosticsForMalformedLink() throws {
        let source = "=>   \nRegular"
        let document = try GemtextParser.parse(source, options: .init(mode: .permissive))
        
        XCTAssertEqual(document.lines.count, 2)
        XCTAssertEqual(document.diagnostics.filter { $0.severity == .error }.count, 1)
        guard case .text = document.lines[0] else {
            return XCTFail("Malformed link should fall back to text in permissive mode")
        }
    }
    
    func testStrictModeThrowsForMalformedLink() {
        let source = "=>   \nRegular"
        XCTAssertThrowsError(
            try GemtextParser.parse(source, options: .init(mode: .strict))
        )
    }
    
    func testAcceptsBareLFAndCRLF() throws {
        let lfSource = "# Title\nText\n"
        let crlfSource = "# Title\r\nText\r\n"
        
        let lfDocument = try GemtextParser.parse(lfSource)
        let crlfDocument = try GemtextParser.parse(crlfSource)
        
        XCTAssertTrue(lfDocument.diagnostics.isEmpty)
        XCTAssertTrue(crlfDocument.diagnostics.isEmpty)
        XCTAssertEqual(lfDocument.lines.count, 2)
        XCTAssertEqual(crlfDocument.lines.count, 2)
    }
    
    func testCRLFAllowedWhenBareLFDisallowed() throws {
        let source = "# Title\r\nText\r\n"
        let document = try GemtextParser.parse(
            source,
            options: .init(allowBareLineFeeds: false)
        )
        
        XCTAssertTrue(document.diagnostics.isEmpty)
    }
    
    func testParserDoesNotCreateTrailingEmptyLineForTerminatedInput() throws {
        let source = "Line one\nLine two\n"
        let document = try GemtextParser.parse(source)
        
        XCTAssertEqual(document.lines.count, 2)
    }
    
    func testPlainTextRendererNormalizationOptions() throws {
        let source = "#  Header  \n=> /x\tLabel\n*  item\n"
        let document = try GemtextParser.parse(source, options: .init(baseURL: URL(string: "gemini://example.org")!))
        
        let rendered = GemtextRenderer.plainText(
            from: document,
            options: .init(normalizeWhitespace: true, includeLinkTargets: true, includePreformatAltText: false, listBullet: "*")
        )
        
        XCTAssertEqual(rendered, "Header\nLabel (/x)\n* item")
    }
    
    func testMarkdownRendererProducesExpectedOutput() throws {
        let source = "# Title\n=> /x Label\n```lang\ncode\n```\n"
        let document = try GemtextParser.parse(source)
        
        let rendered = GemtextRenderer.markdown(
            from: document,
            options: .init(normalizeWhitespace: true, includePreformatAltTextAsInfoString: true)
        )
        
        XCTAssertEqual(rendered, "# Title\n[Label](/x)\n``` lang\ncode\n```")
    }
    
    func testParseDataRequiresUTF8() {
        let invalid = Data([0xFF, 0xFF, 0x00])
        XCTAssertThrowsError(try GemtextParser.parse(invalid))
    }
    
    private func loadFixture(named name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "gmi") else {
            throw NSError(domain: "GemtextParserTests", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
