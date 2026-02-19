//
// CompanionTypes.swift
//
//

import Foundation

/// Configuration for parsing Gemini `robots.txt` content.
public struct GeminiRobotsParserOptions: Sendable {
    /// Parser strictness mode.
    public var mode: GemtextParserMode
    /// Whether standalone LF line endings are accepted.
    public var allowBareLineFeeds: Bool
    
    /// Creates robots parser options.
    public init(
        mode: GemtextParserMode = .permissive,
        allowBareLineFeeds: Bool = true
    ) {
        self.mode = mode
        self.allowBareLineFeeds = allowBareLineFeeds
    }
}

/// Errors thrown by ``GeminiRobotsParser``.
public enum GeminiRobotsParserError: Error, Sendable {
    /// Parsing in strict mode encountered one or more error-level diagnostics.
    case strictModeViolation([GemtextDiagnostic])
    /// Input bytes were not valid UTF-8.
    case invalidUTF8Data
}

/// Standardized virtual user-agents defined by the Gemini companion robots spec.
public enum GeminiRobotsVirtualUserAgent: String, CaseIterable, Sendable {
    /// Archiving crawler behavior.
    case archiver
    /// Indexing/search crawler behavior.
    case indexer
    /// Research crawler behavior.
    case researcher
    /// HTTP web-proxy behavior.
    case webproxy
}

/// Group of robots directives associated with one or more user-agents.
public struct GeminiRobotsGroup: Sendable, Equatable {
    /// User-agent values covered by this group.
    public let userAgents: [String]
    /// Path prefixes disallowed for matching user-agents.
    public let disallowPrefixes: [String]
    
    /// Creates a robots directive group.
    public init(userAgents: [String], disallowPrefixes: [String]) {
        self.userAgents = userAgents
        self.disallowPrefixes = disallowPrefixes
    }
}

/// Parsed robots policy for a Gemini capsule.
public struct GeminiRobotsPolicy: Sendable, Equatable {
    /// Parsed user-agent groups in source order.
    public let groups: [GeminiRobotsGroup]
    /// Diagnostics collected while parsing.
    public let diagnostics: [GemtextDiagnostic]
    
    /// Creates a robots policy value.
    public init(groups: [GeminiRobotsGroup], diagnostics: [GemtextDiagnostic]) {
        self.groups = groups
        self.diagnostics = diagnostics
    }
    
    /// Returns disallowed path prefixes for matching user-agent strings.
    ///
    /// - Parameter userAgents: User-agent strings to match, case-insensitively.
    /// - Returns: De-duplicated disallow prefixes from all matching groups.
    public func disallowPrefixes(for userAgents: [String]) -> [String] {
        let normalizedAgents = Set(userAgents.map { $0.lowercased() })
        var seen: Set<String> = []

        return groups
            .filter { group in
                group.userAgents.contains { agent in
                    let normalized = agent.lowercased()
                    return normalized == "*" || normalizedAgents.contains(normalized)
                }
            }
            .flatMap(\.disallowPrefixes)
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    /// Returns disallowed path prefixes for matching virtual user-agents.
    ///
    /// - Parameter virtualUserAgents: Virtual user-agent categories to match.
    /// - Returns: De-duplicated disallow prefixes from all matching groups.
    public func disallowPrefixes(for virtualUserAgents: [GeminiRobotsVirtualUserAgent]) -> [String] {
        disallowPrefixes(for: virtualUserAgents.map(\.rawValue))
    }
    
    /// Evaluates whether a path or URL is allowed for the supplied user-agent strings.
    ///
    /// - Parameters:
    ///   - pathOrURL: Absolute URL or path to evaluate.
    ///   - userAgents: User-agent strings to match.
    /// - Returns: `true` when the path is not matched by any disallow prefix.
    public func isPathAllowed(_ pathOrURL: String, userAgents: [String]) -> Bool {
        let path = normalizePath(pathOrURL)
        for prefix in disallowPrefixes(for: userAgents) where path.hasPrefix(prefix) {
            return false
        }
        return true
    }

    /// Evaluates whether a path or URL is allowed for the supplied virtual user-agents.
    ///
    /// - Parameters:
    ///   - pathOrURL: Absolute URL or path to evaluate.
    ///   - virtualUserAgents: Virtual user-agent categories to match.
    /// - Returns: `true` when the path is not matched by any disallow prefix.
    public func isPathAllowed(_ pathOrURL: String, virtualUserAgents: [GeminiRobotsVirtualUserAgent]) -> Bool {
        isPathAllowed(pathOrURL, userAgents: virtualUserAgents.map(\.rawValue))
    }
    
    private func normalizePath(_ pathOrURL: String) -> String {
        if let url = URL(string: pathOrURL), url.scheme != nil {
            return url.path.isEmpty ? "/" : url.path
        }
        
        if pathOrURL.isEmpty {
            return "/"
        }
        
        if pathOrURL.hasPrefix("/") {
            return pathOrURL
        }
        
        return "/" + pathOrURL
    }
}

/// Configuration for parsing Gemtext subscription feeds.
public struct GeminiSubscriptionParserOptions: Sendable {
    /// Parser strictness mode.
    public var mode: GemtextParserMode
    /// Fallback `updated` timestamp used when no entries are extracted.
    public var fetchedAt: Date
    /// Whether standalone LF line endings are accepted.
    public var allowBareLineFeeds: Bool
    
    /// Creates subscription parser options.
    public init(
        mode: GemtextParserMode = .permissive,
        fetchedAt: Date = Date(),
        allowBareLineFeeds: Bool = true
    ) {
        self.mode = mode
        self.fetchedAt = fetchedAt
        self.allowBareLineFeeds = allowBareLineFeeds
    }
}

/// Errors thrown by ``GeminiSubscriptionParser``.
public enum GeminiSubscriptionParserError: Error, Sendable {
    /// Parsing in strict mode encountered one or more error-level diagnostics.
    case strictModeViolation([GemtextDiagnostic])
    /// Input bytes were not valid UTF-8.
    case invalidUTF8Data
}

/// Entry extracted from a Gemtext subscription feed.
public struct GeminiSubscriptionEntry: Sendable, Equatable {
    /// Atom-equivalent entry id value.
    public let id: URL
    /// Atom-equivalent entry alternate link.
    public let link: URL
    /// Entry update time (noon UTC on parsed date).
    public let updated: Date
    /// Entry title derived from the link label.
    public let title: String
    /// 1-based source line number of the corresponding link.
    public let sourceLine: Int
    
    /// Creates a subscription entry.
    public init(id: URL, link: URL, updated: Date, title: String, sourceLine: Int) {
        self.id = id
        self.link = link
        self.updated = updated
        self.title = title
        self.sourceLine = sourceLine
    }
}

/// Parsed Gemtext subscription feed.
public struct GeminiSubscriptionFeed: Sendable, Equatable {
    /// Feed id (the fetched document URL).
    public let id: URL
    /// Feed link (the fetched document URL).
    public let link: URL
    /// Feed title (first level-1 heading).
    public let title: String
    /// Optional feed subtitle (early level-2 heading per companion spec convention).
    public let subtitle: String?
    /// Feed update time (`max(entry.updated)` or `fetchedAt` fallback).
    public let updated: Date
    /// Extracted entries in source order.
    public let entries: [GeminiSubscriptionEntry]
    /// Diagnostics collected while parsing.
    public let diagnostics: [GemtextDiagnostic]
    
    /// Creates a subscription feed value.
    public init(
        id: URL,
        link: URL,
        title: String,
        subtitle: String?,
        updated: Date,
        entries: [GeminiSubscriptionEntry],
        diagnostics: [GemtextDiagnostic]
    ) {
        self.id = id
        self.link = link
        self.title = title
        self.subtitle = subtitle
        self.updated = updated
        self.entries = entries
        self.diagnostics = diagnostics
    }
}
