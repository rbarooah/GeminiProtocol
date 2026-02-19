//
// GemtextParser.swift
//
//

import Foundation

private struct GemtextSourceLine {
    let number: Int
    let raw: String
}

/// Parser for `text/gemini` documents.
public enum GemtextParser {
    /// Parses a UTF-8 string into a ``GemtextDocument``.
    ///
    /// - Parameters:
    ///   - source: Gemtext source text.
    ///   - options: Parser behavior options.
    /// - Returns: Parsed document with typed lines and diagnostics.
    /// - Throws: ``GemtextParserError/strictModeViolation(_:)`` when strict mode encounters errors.
    public static func parse(
        _ source: String,
        options: GemtextParserOptions = .init()
    ) throws -> GemtextDocument {
        var diagnostics: [GemtextDiagnostic] = []
        let lines = tokenize(source: source, options: options, diagnostics: &diagnostics)
        
        var inPreformatted = false
        var parsed: [GemtextLine] = []
        parsed.reserveCapacity(lines.count)
        
        for line in lines {
            parse(
                sourceLine: line,
                inPreformatted: &inPreformatted,
                options: options,
                diagnostics: &diagnostics,
                parsed: &parsed
            )
        }
        
        if inPreformatted {
            diagnostics.append(
                GemtextDiagnostic(
                    line: max(lines.last?.number ?? 1, 1),
                    column: 1,
                    severity: .warning,
                    message: "Document ends while still in preformatted mode"
                )
            )
        }
        
        if options.mode == .strict {
            let errors = diagnostics.filter { $0.severity == .error }
            if !errors.isEmpty {
                throw GemtextParserError.strictModeViolation(errors)
            }
        }
        
        return GemtextDocument(source: source, lines: parsed, diagnostics: diagnostics)
    }
    
    /// Parses UTF-8 bytes into a ``GemtextDocument``.
    ///
    /// - Parameters:
    ///   - data: UTF-8 encoded gemtext bytes.
    ///   - options: Parser behavior options.
    /// - Returns: Parsed document with typed lines and diagnostics.
    /// - Throws: ``GemtextParserError/invalidUTF8Data`` when data is not valid UTF-8.
    public static func parse(
        _ data: Data,
        options: GemtextParserOptions = .init()
    ) throws -> GemtextDocument {
        guard let source = String(data: data, encoding: .utf8) else {
            throw GemtextParserError.invalidUTF8Data
        }
        
        return try parse(source, options: options)
    }
    
    private static func tokenize(
        source: String,
        options: GemtextParserOptions,
        diagnostics: inout [GemtextDiagnostic]
    ) -> [GemtextSourceLine] {
        if !options.allowBareLineFeeds {
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
        
        var working = source.replacingOccurrences(of: "\r\n", with: "\n")
        if working.contains("\r") {
            diagnostics.append(
                GemtextDiagnostic(
                    line: 1,
                    column: 1,
                    severity: .error,
                    message: "Found carriage returns not followed by line feed"
                )
            )
        }
        working = working.replacingOccurrences(of: "\r", with: "\n")
        
        if !source.isEmpty && !source.hasSuffix("\n") && !source.hasSuffix("\r\n") {
            let lineCount = splitLinesPreservingEmptyContent(working).count
            diagnostics.append(
                GemtextDiagnostic(
                    line: max(lineCount, 1),
                    column: 1,
                    severity: .warning,
                    message: "Final line has no line terminator"
                )
            )
        }
        
        let split = splitLinesPreservingEmptyContent(working)
        return split.enumerated().map { index, value in
            GemtextSourceLine(number: index + 1, raw: value)
        }
    }
    
    private static func parse(
        sourceLine: GemtextSourceLine,
        inPreformatted: inout Bool,
        options: GemtextParserOptions,
        diagnostics: inout [GemtextDiagnostic],
        parsed: inout [GemtextLine]
    ) {
        let raw = sourceLine.raw
        let lineNumber = sourceLine.number
        
        if raw.hasPrefix("```") {
            let toggle = GemtextPreformatToggleLine(
                lineNumber: lineNumber,
                raw: raw,
                altText: String(raw.dropFirst(3)),
                entersPreformatted: !inPreformatted
            )
            inPreformatted.toggle()
            parsed.append(.preformatToggle(toggle))
            return
        }
        
        if inPreformatted {
            parsed.append(
                .text(
                    GemtextTextLine(
                        lineNumber: lineNumber,
                        raw: raw,
                        text: raw,
                        isPreformatted: true
                    )
                )
            )
            return
        }
        
        if raw.hasPrefix("=>") {
            if let link = parseLink(raw: raw, lineNumber: lineNumber, baseURL: options.baseURL, diagnostics: &diagnostics) {
                parsed.append(.link(link))
            } else {
                parsed.append(
                    .text(
                        GemtextTextLine(
                            lineNumber: lineNumber,
                            raw: raw,
                            text: raw,
                            isPreformatted: false
                        )
                    )
                )
            }
            return
        }
        
        if raw.hasPrefix("###") {
            parsed.append(.heading(parseHeading(raw: raw, lineNumber: lineNumber, level: 3, markerLength: 3)))
            return
        }
        if raw.hasPrefix("##") {
            parsed.append(.heading(parseHeading(raw: raw, lineNumber: lineNumber, level: 2, markerLength: 2)))
            return
        }
        if raw.hasPrefix("#") {
            parsed.append(.heading(parseHeading(raw: raw, lineNumber: lineNumber, level: 1, markerLength: 1)))
            return
        }
        if raw.hasPrefix("* ") {
            let text = String(raw.dropFirst(2))
            parsed.append(
                .listItem(
                    GemtextListItemLine(lineNumber: lineNumber, raw: raw, text: text)
                )
            )
            return
        }
        if raw.hasPrefix(">") {
            let text = String(raw.dropFirst())
            parsed.append(
                .quote(
                    GemtextQuoteLine(lineNumber: lineNumber, raw: raw, text: text)
                )
            )
            return
        }
        
        parsed.append(
            .text(
                GemtextTextLine(
                    lineNumber: lineNumber,
                    raw: raw,
                    text: raw,
                    isPreformatted: false
                )
            )
        )
    }
    
    private static func parseHeading(raw: String, lineNumber: Int, level: Int, markerLength: Int) -> GemtextHeadingLine {
        let body = trimLeadingHorizontalWhitespace(String(raw.dropFirst(markerLength)))
        return GemtextHeadingLine(lineNumber: lineNumber, raw: raw, level: level, text: body)
    }
    
    private static func parseLink(
        raw: String,
        lineNumber: Int,
        baseURL: URL?,
        diagnostics: inout [GemtextDiagnostic]
    ) -> GemtextLinkLine? {
        let body = raw.dropFirst(2)
        guard let urlStart = body.firstIndex(where: { !isHorizontalWhitespace($0) }) else {
            diagnostics.append(
                GemtextDiagnostic(
                    line: lineNumber,
                    column: 1,
                    severity: .error,
                    message: "Link line is missing URL target"
                )
            )
            return nil
        }
        
        let afterWhitespace = body[urlStart...]
        let urlEnd = afterWhitespace.firstIndex(where: isHorizontalWhitespace) ?? afterWhitespace.endIndex
        let target = String(afterWhitespace[..<urlEnd])
        guard !target.isEmpty else {
            diagnostics.append(
                GemtextDiagnostic(
                    line: lineNumber,
                    column: 1,
                    severity: .error,
                    message: "Link line is missing URL target"
                )
            )
            return nil
        }
        
        let remainder = afterWhitespace[urlEnd...]
        var label: String?
        if let labelStart = remainder.firstIndex(where: { !isHorizontalWhitespace($0) }) {
            label = trimTrailingHorizontalWhitespace(String(remainder[labelStart...]))
        } else if !remainder.isEmpty {
            diagnostics.append(
                GemtextDiagnostic(
                    line: lineNumber,
                    column: 1,
                    severity: .error,
                    message: "Link line has whitespace but no label"
                )
            )
            return nil
        }
        
        let resolvedURL = resolveURL(target: target, baseURL: baseURL)
        if resolvedURL == nil {
            diagnostics.append(
                GemtextDiagnostic(
                    line: lineNumber,
                    column: 1,
                    severity: .warning,
                    message: "Could not resolve link URL: \(target)"
                )
            )
        }
        
        return GemtextLinkLine(
            lineNumber: lineNumber,
            raw: raw,
            target: target,
            label: label,
            resolvedURL: resolvedURL
        )
    }
    
    private static func resolveURL(target: String, baseURL: URL?) -> URL? {
        if let url = URL(string: target), url.scheme != nil {
            return url
        }
        
        if let baseURL {
            return URL(string: target, relativeTo: baseURL)?.absoluteURL
        }
        
        return nil
    }
    
    private static func isHorizontalWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }
    
    private static func trimLeadingHorizontalWhitespace(_ value: String) -> String {
        String(value.drop { isHorizontalWhitespace($0) })
    }
    
    private static func trimTrailingHorizontalWhitespace(_ value: String) -> String {
        let trimmed = value.reversed().drop { isHorizontalWhitespace($0) }
        return String(trimmed.reversed())
    }
    
    private static func splitLinesPreservingEmptyContent(_ normalized: String) -> [String] {
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
}
