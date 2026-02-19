//
// CompanionParsers.swift
//
//

import Foundation

private struct CompanionSourceLine {
    let number: Int
    let raw: String
}

/// Parser for Gemini companion `robots.txt` documents.
public enum GeminiRobotsParser {
    /// Parses robots policy text.
    ///
    /// - Parameters:
    ///   - source: Robots source text.
    ///   - options: Parser behavior options.
    /// - Returns: Parsed robots policy and diagnostics.
    /// - Throws: ``GeminiRobotsParserError/strictModeViolation(_:)`` in strict mode.
    public static func parse(
        _ source: String,
        options: GeminiRobotsParserOptions = .init()
    ) throws -> GeminiRobotsPolicy {
        var diagnostics: [GemtextDiagnostic] = []
        let lines = tokenize(
            source: source,
            allowBareLineFeeds: options.allowBareLineFeeds,
            diagnostics: &diagnostics
        )
        
        var groups: [GeminiRobotsGroup] = []
        var currentAgents: [String] = []
        var currentDisallow: [String] = []
        
        func flushCurrentGroup() {
            guard !currentAgents.isEmpty else { return }
            groups.append(
                GeminiRobotsGroup(
                    userAgents: currentAgents,
                    disallowPrefixes: currentDisallow
                )
            )
            currentAgents = []
            currentDisallow = []
        }
        
        for line in lines {
            let trimmedLeading = line.raw.drop { $0 == " " || $0 == "\t" }
            if trimmedLeading.isEmpty {
                flushCurrentGroup()
                continue
            }
            
            if trimmedLeading.first == "#" {
                continue
            }
            
            guard let separator = trimmedLeading.firstIndex(of: ":") else {
                continue
            }
            
            let directive = trimmedLeading[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = trimmedLeading[trimmedLeading.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            switch directive {
            case "user-agent":
                guard !value.isEmpty else {
                    diagnostics.append(
                        GemtextDiagnostic(
                            line: line.number,
                            column: 1,
                            severity: .error,
                            message: "User-agent directive is missing a value"
                        )
                    )
                    continue
                }
                
                if !currentDisallow.isEmpty {
                    flushCurrentGroup()
                }
                currentAgents.append(value)
            case "disallow":
                guard !currentAgents.isEmpty else {
                    diagnostics.append(
                        GemtextDiagnostic(
                            line: line.number,
                            column: 1,
                            severity: .error,
                            message: "Disallow directive appears before any User-agent directive"
                        )
                    )
                    continue
                }
                
                currentDisallow.append(value)
            default:
                continue
            }
        }
        
        flushCurrentGroup()
        try validateStrictMode(mode: options.mode, diagnostics: diagnostics, error: GeminiRobotsParserError.strictModeViolation)
        
        return GeminiRobotsPolicy(groups: groups, diagnostics: diagnostics)
    }
    
    /// Parses UTF-8 robots policy bytes.
    ///
    /// - Parameters:
    ///   - data: UTF-8 encoded robots text.
    ///   - options: Parser behavior options.
    /// - Returns: Parsed robots policy and diagnostics.
    /// - Throws: ``GeminiRobotsParserError/invalidUTF8Data`` for non-UTF-8 input.
    public static func parse(
        _ data: Data,
        options: GeminiRobotsParserOptions = .init()
    ) throws -> GeminiRobotsPolicy {
        guard let source = String(data: data, encoding: .utf8) else {
            throw GeminiRobotsParserError.invalidUTF8Data
        }
        
        return try parse(source, options: options)
    }
}

/// Parser for Gemtext subscription-feed companion convention documents.
public enum GeminiSubscriptionParser {
    /// Parses Gemtext feed source text.
    ///
    /// - Parameters:
    ///   - source: Feed source text.
    ///   - feedURL: URL from which the feed was fetched.
    ///   - options: Parser behavior options.
    /// - Returns: Parsed subscription feed and diagnostics.
    /// - Throws: ``GeminiSubscriptionParserError/strictModeViolation(_:)`` in strict mode.
    public static func parse(
        _ source: String,
        feedURL: URL,
        options: GeminiSubscriptionParserOptions = .init()
    ) throws -> GeminiSubscriptionFeed {
        let document = try GemtextParser.parse(
            source,
            options: .init(
                mode: .permissive,
                baseURL: feedURL,
                allowBareLineFeeds: options.allowBareLineFeeds
            )
        )
        return try parse(document, feedURL: feedURL, options: options)
    }
    
    /// Parses UTF-8 Gemtext feed bytes.
    ///
    /// - Parameters:
    ///   - data: UTF-8 encoded feed source.
    ///   - feedURL: URL from which the feed was fetched.
    ///   - options: Parser behavior options.
    /// - Returns: Parsed subscription feed and diagnostics.
    /// - Throws: ``GeminiSubscriptionParserError/invalidUTF8Data`` for non-UTF-8 input.
    public static func parse(
        _ data: Data,
        feedURL: URL,
        options: GeminiSubscriptionParserOptions = .init()
    ) throws -> GeminiSubscriptionFeed {
        guard let source = String(data: data, encoding: .utf8) else {
            throw GeminiSubscriptionParserError.invalidUTF8Data
        }
        
        return try parse(source, feedURL: feedURL, options: options)
    }
    
    /// Builds a subscription feed from an already parsed gemtext document.
    ///
    /// - Parameters:
    ///   - document: Parsed gemtext document.
    ///   - feedURL: URL from which the document was fetched.
    ///   - options: Parser behavior options.
    /// - Returns: Parsed subscription feed and diagnostics.
    /// - Throws: ``GeminiSubscriptionParserError/strictModeViolation(_:)`` in strict mode.
    public static func parse(
        _ document: GemtextDocument,
        feedURL: URL,
        options: GeminiSubscriptionParserOptions = .init()
    ) throws -> GeminiSubscriptionFeed {
        var diagnostics = document.diagnostics
        
        let titleMatch = firstFeedTitle(in: document.lines)
        if titleMatch == nil {
            diagnostics.append(
                GemtextDiagnostic(
                    line: 1,
                    column: 1,
                    severity: .error,
                    message: "Subscription feed is missing a level-1 heading for the feed title"
                )
            )
        }
        
        let subtitle = subtitleFromDocument(
            lines: document.lines,
            titleLineIndex: titleMatch?.lineIndex
        )
        
        let entries = extractEntries(
            from: document.lines,
            feedURL: feedURL,
            diagnostics: &diagnostics
        )
        
        let updated = entries.map(\.updated).max() ?? options.fetchedAt
        try validateStrictMode(mode: options.mode, diagnostics: diagnostics, error: GeminiSubscriptionParserError.strictModeViolation)
        
        return GeminiSubscriptionFeed(
            id: feedURL,
            link: feedURL,
            title: titleMatch?.text ?? feedURL.absoluteString,
            subtitle: subtitle,
            updated: updated,
            entries: entries,
            diagnostics: diagnostics
        )
    }
    
    private static func firstFeedTitle(in lines: [GemtextLine]) -> (lineIndex: Int, text: String)? {
        for (index, line) in lines.enumerated() {
            guard case .heading(let heading) = line, heading.level == 1 else {
                continue
            }
            return (lineIndex: index, text: heading.text)
        }
        return nil
    }
    
    private static func subtitleFromDocument(lines: [GemtextLine], titleLineIndex: Int?) -> String? {
        guard let titleLineIndex else { return nil }
        
        var subtitle: String?
        for line in lines.dropFirst(titleLineIndex + 1) {
            switch line {
            case .heading(let heading):
                if heading.level == 2, subtitle == nil {
                    subtitle = heading.text
                }
            case .text(let textLine):
                if textLine.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continue
                }
                return subtitle
            case .link, .listItem, .quote, .preformatToggle:
                return subtitle
            }
        }
        
        return subtitle
    }
    
    private static func extractEntries(
        from lines: [GemtextLine],
        feedURL: URL,
        diagnostics: inout [GemtextDiagnostic]
    ) -> [GeminiSubscriptionEntry] {
        var entries: [GeminiSubscriptionEntry] = []
        
        for line in lines {
            guard case .link(let linkLine) = line else { continue }
            guard let label = linkLine.label, label.count >= 10 else { continue }
            
            let datePrefix = String(label.prefix(10))
            guard looksLikeISODate(datePrefix) else { continue }
            
            guard let updated = middayUTC(forDatePrefix: datePrefix) else {
                diagnostics.append(
                    GemtextDiagnostic(
                        line: linkLine.lineNumber,
                        column: 1,
                        severity: .warning,
                        message: "Subscription entry date is not a valid calendar date: \(datePrefix)"
                    )
                )
                continue
            }
            
            guard let entryURL = resolvedLinkURL(linkLine, feedURL: feedURL) else {
                diagnostics.append(
                    GemtextDiagnostic(
                        line: linkLine.lineNumber,
                        column: 1,
                        severity: .error,
                        message: "Subscription entry URL could not be resolved: \(linkLine.target)"
                    )
                )
                continue
            }
            
            let rawRemainder = subscriptionTitleRemainder(fromLabel: label)
            var title = sanitizeSubscriptionTitle(rawRemainder)
            if title.isEmpty {
                diagnostics.append(
                    GemtextDiagnostic(
                        line: linkLine.lineNumber,
                        column: 1,
                        severity: .warning,
                        message: "Subscription entry title is empty after date prefix; using URL as title"
                    )
                )
                title = entryURL.absoluteString
            }
            
            entries.append(
                GeminiSubscriptionEntry(
                    id: entryURL,
                    link: entryURL,
                    updated: updated,
                    title: title,
                    sourceLine: linkLine.lineNumber
                )
            )
        }
        
        return entries
    }
    
    private static func resolvedLinkURL(_ line: GemtextLinkLine, feedURL: URL) -> URL? {
        if let resolved = line.resolvedURL {
            return resolved
        }
        
        if let absolute = URL(string: line.target), absolute.scheme != nil {
            return absolute
        }
        
        return URL(string: line.target, relativeTo: feedURL)?.absoluteURL
    }
    
    private static func looksLikeISODate(_ datePrefix: String) -> Bool {
        guard datePrefix.count == 10 else { return false }
        let chars = Array(datePrefix)
        guard chars[4] == "-", chars[7] == "-" else { return false }
        
        let positions = [0, 1, 2, 3, 5, 6, 8, 9]
        return positions.allSatisfy { chars[$0].isNumber }
    }
    
    private static func middayUTC(forDatePrefix datePrefix: String) -> Date? {
        let parts = datePrefix.split(separator: "-")
        guard parts.count == 3 else { return nil }
        guard
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12,
            minute: 0,
            second: 0
        )

        guard let date = calendar.date(from: components) else {
            return nil
        }

        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            return nil
        }

        return date
    }
    
    private static func sanitizeSubscriptionTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = title.first, first == "-" || first == ":" || first == "|" {
            title.removeFirst()
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title
    }

    private static func subscriptionTitleRemainder(fromLabel label: String) -> String {
        guard let whitespaceIndex = label.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return ""
        }

        return label[whitespaceIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func tokenize(
    source: String,
    allowBareLineFeeds: Bool,
    diagnostics: inout [GemtextDiagnostic]
) -> [CompanionSourceLine] {
    if !allowBareLineFeeds {
        let withoutCRLF = source.replacingOccurrences(of: "\r\n", with: "")
        if withoutCRLF.contains("\n") {
            diagnostics.append(
                GemtextDiagnostic(
                    line: 1,
                    column: 1,
                    severity: .error,
                    message: "Bare line feeds are not allowed with current parser options"
                )
            )
        }
    }
    
    var normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
    if normalized.contains("\r") {
        diagnostics.append(
            GemtextDiagnostic(
                line: 1,
                column: 1,
                severity: .error,
                message: "Found carriage returns not followed by line feed"
            )
        )
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")
    }
    
    let splitLines = splitLinesPreservingEmptyContent(normalized)
    return splitLines.enumerated().map { index, value in
        CompanionSourceLine(number: index + 1, raw: value)
    }
}

private func splitLinesPreservingEmptyContent(_ normalized: String) -> [String] {
    var lines: [String] = []
    var lineStart = normalized.startIndex
    
    for index in normalized.indices where normalized[index] == "\n" {
        lines.append(String(normalized[lineStart..<index]))
        lineStart = normalized.index(after: index)
    }
    
    if lineStart < normalized.endIndex {
        lines.append(String(normalized[lineStart...]))
    } else if lines.isEmpty {
        lines.append("")
    }
    
    return lines
}

private func validateStrictMode<E: Error>(
    mode: GemtextParserMode,
    diagnostics: [GemtextDiagnostic],
    error: ([GemtextDiagnostic]) -> E
) throws {
    guard mode == .strict else { return }
    let errors = diagnostics.filter { $0.severity == .error }
    if !errors.isEmpty {
        throw error(errors)
    }
}
