//
// CompanionParserTests.swift
//
// Copyright (c) 2022 Izzy Fraimow. All rights reserved.
//

import Foundation
import XCTest
@testable import GeminiProtocol

final class CompanionParserTests: XCTestCase {
    func testRobotsParserParsesGroupsAndPolicyMatching() throws {
        let source = try loadFixture(named: "robots", ext: "txt")
        let policy = try GeminiRobotsParser.parse(source)
        
        XCTAssertTrue(policy.diagnostics.isEmpty)
        XCTAssertEqual(policy.groups.count, 3)
        XCTAssertEqual(
            policy.disallowPrefixes(for: [.indexer]),
            ["/private", "/tmp", "/search"]
        )
        XCTAssertFalse(policy.isPathAllowed("/private/notes.gmi", virtualUserAgents: [.indexer]))
        XCTAssertFalse(policy.isPathAllowed("/search/index.gmi", virtualUserAgents: [.indexer]))
        XCTAssertTrue(policy.isPathAllowed("/public/post.gmi", virtualUserAgents: [.indexer]))
    }
    
    func testRobotsParserStrictModeRejectsDirectiveBeforeUserAgent() throws {
        let source = "Disallow: /private\n"
        let permissive = try GeminiRobotsParser.parse(source, options: .init(mode: .permissive))
        
        XCTAssertEqual(permissive.groups.count, 0)
        XCTAssertEqual(permissive.diagnostics.filter { $0.severity == .error }.count, 1)
        XCTAssertThrowsError(
            try GeminiRobotsParser.parse(source, options: .init(mode: .strict))
        )
    }
    
    func testRobotsParserRejectsInvalidUTF8Data() {
        let invalid = Data([0xFF, 0x00, 0xFF])
        XCTAssertThrowsError(try GeminiRobotsParser.parse(invalid))
    }
    
    func testSubscriptionParserExtractsFeedAndEntries() throws {
        let source = try loadFixture(named: "subscription", ext: "gmi")
        let feedURL = URL(string: "gemini://example.org/gemlog/")!
        let feed = try GeminiSubscriptionParser.parse(source, feedURL: feedURL)
        
        XCTAssertTrue(feed.diagnostics.isEmpty)
        XCTAssertEqual(feed.id, feedURL)
        XCTAssertEqual(feed.link, feedURL)
        XCTAssertEqual(feed.title, "Example Capsule Log")
        XCTAssertEqual(feed.subtitle, "Recent Posts")
        XCTAssertEqual(feed.entries.count, 2)
        XCTAssertEqual(feed.entries[0].link.absoluteString, "gemini://example.org/gemlog/first.gmi")
        XCTAssertEqual(feed.entries[0].title, "First post")
        XCTAssertEqual(feed.entries[0].sourceLine, 4)
        XCTAssertEqual(feed.entries[1].title, "Second post")
        XCTAssertEqual(feed.updated, try XCTUnwrap(makeUTCDate(year: 2026, month: 2, day: 18, hour: 12)))
    }
    
    func testSubscriptionParserUsesFetchedTimeWhenNoEntries() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_730_000_000)
        let source = "# Empty Feed\nNo dated links here\n"
        let feed = try GeminiSubscriptionParser.parse(
            source,
            feedURL: URL(string: "gemini://example.org/empty/")!,
            options: .init(fetchedAt: fetchedAt)
        )
        
        XCTAssertEqual(feed.entries.count, 0)
        XCTAssertEqual(feed.updated, fetchedAt)
    }
    
    func testSubscriptionParserStrictModeRejectsMissingTitle() {
        let source = "=> post.gmi 2026-02-18 A post\n"
        XCTAssertThrowsError(
            try GeminiSubscriptionParser.parse(
                source,
                feedURL: URL(string: "gemini://example.org/gemlog/")!,
                options: .init(mode: .strict)
            )
        )
    }
    
    func testSubscriptionParserReportsInvalidDatePrefix() throws {
        let source = """
        # Feed Title
        => post.gmi 2026-02-31 Invalid date
        """
        let feed = try GeminiSubscriptionParser.parse(
            source,
            feedURL: URL(string: "gemini://example.org/gemlog/")!
        )
        
        XCTAssertEqual(feed.entries.count, 0)
        XCTAssertTrue(feed.diagnostics.contains { $0.message.contains("not a valid calendar date") })
    }
    
    func testSubscriptionParserRejectsInvalidUTF8Data() {
        let invalid = Data([0xFF, 0x00, 0xFF])
        XCTAssertThrowsError(
            try GeminiSubscriptionParser.parse(
                invalid,
                feedURL: URL(string: "gemini://example.org/gemlog/")!
            )
        )
    }

    func testSubscriptionParserDropsFirstWhitespaceComponentForTitle() throws {
        let source = """
        # Feed Title
        => post.gmi 2026-02-18Title Part Two
        """
        let feed = try GeminiSubscriptionParser.parse(
            source,
            feedURL: URL(string: "gemini://example.org/gemlog/")!
        )

        XCTAssertEqual(feed.entries.count, 1)
        XCTAssertEqual(feed.entries[0].title, "Part Two")
    }
    
    private func loadFixture(named name: String, ext: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw NSError(domain: "CompanionParserTests", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
    
    private func makeUTCDate(year: Int, month: Int, day: Int, hour: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: 0,
                second: 0
            )
        )
    }
}
