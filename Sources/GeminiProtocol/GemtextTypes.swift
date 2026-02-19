//
// GemtextTypes.swift
//
//

import Foundation

/// Error-handling mode used by gemtext and companion parsers.
public enum GemtextParserMode: Sendable {
    /// Collects diagnostics and returns a result whenever possible.
    case permissive
    /// Throws when error-level diagnostics are encountered.
    case strict
}

/// Configuration for parsing `text/gemini` content.
public struct GemtextParserOptions: Sendable {
    /// Parser strictness mode.
    public var mode: GemtextParserMode
    /// Base URL used to resolve relative link targets.
    public var baseURL: URL?
    /// Whether standalone LF line endings are accepted.
    public var allowBareLineFeeds: Bool
    
    /// Creates parser options.
    ///
    /// - Parameters:
    ///   - mode: Parser strictness mode.
    ///   - baseURL: Base URL used to resolve relative links.
    ///   - allowBareLineFeeds: Accept LF-only line endings when `true`.
    public init(
        mode: GemtextParserMode = .permissive,
        baseURL: URL? = nil,
        allowBareLineFeeds: Bool = true
    ) {
        self.mode = mode
        self.baseURL = baseURL
        self.allowBareLineFeeds = allowBareLineFeeds
    }
}

/// Severity associated with a parsing diagnostic.
public enum GemtextDiagnosticSeverity: String, Sendable {
    /// Non-fatal issue; parsing continues.
    case warning
    /// Protocol/format error.
    case error
}

/// Structured parser diagnostic emitted for a source line.
public struct GemtextDiagnostic: Sendable, Equatable {
    /// 1-based source line number.
    public let line: Int
    /// 1-based source column number.
    public let column: Int
    /// Diagnostic severity.
    public let severity: GemtextDiagnosticSeverity
    /// Human-readable diagnostic message.
    public let message: String
    
    /// Creates a parsing diagnostic.
    public init(line: Int, column: Int, severity: GemtextDiagnosticSeverity, message: String) {
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
    }
}

/// Errors thrown by ``GemtextParser``.
public enum GemtextParserError: Error, Sendable {
    /// Parsing in strict mode encountered one or more error-level diagnostics.
    case strictModeViolation([GemtextDiagnostic])
    /// Input bytes were not valid UTF-8.
    case invalidUTF8Data
}

/// Parsed gemtext document with source, typed lines, and diagnostics.
public struct GemtextDocument: Sendable, Equatable {
    /// Original source text passed to the parser.
    public let source: String
    /// Parsed line nodes.
    public let lines: [GemtextLine]
    /// Diagnostics collected while parsing.
    public let diagnostics: [GemtextDiagnostic]
    
    /// Creates a parsed gemtext document.
    public init(source: String, lines: [GemtextLine], diagnostics: [GemtextDiagnostic]) {
        self.source = source
        self.lines = lines
        self.diagnostics = diagnostics
    }
}

/// Parsed text line.
public struct GemtextTextLine: Sendable, Equatable {
    /// 1-based source line number.
    public let lineNumber: Int
    /// Unmodified source line text.
    public let raw: String
    /// Parsed/normalized text payload for this line type.
    public let text: String
    /// Indicates whether this text line appears within a preformatted block.
    public let isPreformatted: Bool
    
    /// Creates a parsed text line node.
    public init(lineNumber: Int, raw: String, text: String, isPreformatted: Bool) {
        self.lineNumber = lineNumber
        self.raw = raw
        self.text = text
        self.isPreformatted = isPreformatted
    }
}

/// Parsed link line.
public struct GemtextLinkLine: Sendable, Equatable {
    /// 1-based source line number.
    public let lineNumber: Int
    /// Unmodified source line text.
    public let raw: String
    /// Raw link target as written in source.
    public let target: String
    /// Optional user-facing link label.
    public let label: String?
    /// Resolved absolute URL when resolution succeeds.
    public let resolvedURL: URL?
    
    /// Creates a parsed link line node.
    public init(lineNumber: Int, raw: String, target: String, label: String?, resolvedURL: URL?) {
        self.lineNumber = lineNumber
        self.raw = raw
        self.target = target
        self.label = label
        self.resolvedURL = resolvedURL
    }
}

/// Parsed heading line.
public struct GemtextHeadingLine: Sendable, Equatable {
    /// 1-based source line number.
    public let lineNumber: Int
    /// Unmodified source line text.
    public let raw: String
    /// Heading level (`1...3` in gemtext source).
    public let level: Int
    /// Heading text content.
    public let text: String
    
    /// Creates a parsed heading line node.
    public init(lineNumber: Int, raw: String, level: Int, text: String) {
        self.lineNumber = lineNumber
        self.raw = raw
        self.level = level
        self.text = text
    }
}

/// Parsed list item line.
public struct GemtextListItemLine: Sendable, Equatable {
    /// 1-based source line number.
    public let lineNumber: Int
    /// Unmodified source line text.
    public let raw: String
    /// List item text content.
    public let text: String
    
    /// Creates a parsed list item line node.
    public init(lineNumber: Int, raw: String, text: String) {
        self.lineNumber = lineNumber
        self.raw = raw
        self.text = text
    }
}

/// Parsed quote line.
public struct GemtextQuoteLine: Sendable, Equatable {
    /// 1-based source line number.
    public let lineNumber: Int
    /// Unmodified source line text.
    public let raw: String
    /// Quote text content.
    public let text: String
    
    /// Creates a parsed quote line node.
    public init(lineNumber: Int, raw: String, text: String) {
        self.lineNumber = lineNumber
        self.raw = raw
        self.text = text
    }
}

/// Parsed preformat toggle line.
public struct GemtextPreformatToggleLine: Sendable, Equatable {
    /// 1-based source line number.
    public let lineNumber: Int
    /// Unmodified source line text.
    public let raw: String
    /// Raw alt-text payload after the leading triple backticks.
    public let altText: String
    /// `true` when this toggle enters preformatted mode, `false` when it exits.
    public let entersPreformatted: Bool
    
    /// Creates a parsed preformat toggle line node.
    public init(lineNumber: Int, raw: String, altText: String, entersPreformatted: Bool) {
        self.lineNumber = lineNumber
        self.raw = raw
        self.altText = altText
        self.entersPreformatted = entersPreformatted
    }
}

/// Union of all supported parsed gemtext line node types.
public enum GemtextLine: Sendable, Equatable {
    /// Text line node.
    case text(GemtextTextLine)
    /// Link line node.
    case link(GemtextLinkLine)
    /// Heading line node.
    case heading(GemtextHeadingLine)
    /// List-item line node.
    case listItem(GemtextListItemLine)
    /// Quote line node.
    case quote(GemtextQuoteLine)
    /// Preformat-toggle line node.
    case preformatToggle(GemtextPreformatToggleLine)
    
    /// 1-based source line number for the underlying node.
    public var lineNumber: Int {
        switch self {
        case .text(let line):
            return line.lineNumber
        case .link(let line):
            return line.lineNumber
        case .heading(let line):
            return line.lineNumber
        case .listItem(let line):
            return line.lineNumber
        case .quote(let line):
            return line.lineNumber
        case .preformatToggle(let line):
            return line.lineNumber
        }
    }
    
    /// Unmodified source line for the underlying node.
    public var raw: String {
        switch self {
        case .text(let line):
            return line.raw
        case .link(let line):
            return line.raw
        case .heading(let line):
            return line.raw
        case .listItem(let line):
            return line.raw
        case .quote(let line):
            return line.raw
        case .preformatToggle(let line):
            return line.raw
        }
    }
}

/// Plain-text rendering options for ``GemtextRenderer/plainText(from:options:)``.
public struct GemtextPlainTextRenderOptions: Sendable {
    /// Collapses consecutive spaces/tabs and trims horizontal edge whitespace when `true`.
    public var normalizeWhitespace: Bool
    /// Appends raw link targets to rendered labels when `true`.
    public var includeLinkTargets: Bool
    /// Emits alt text labels for preformat entry toggles when `true`.
    public var includePreformatAltText: Bool
    /// Bullet marker used for rendered list items.
    public var listBullet: String
    
    /// Creates plain-text render options.
    public init(
        normalizeWhitespace: Bool = false,
        includeLinkTargets: Bool = true,
        includePreformatAltText: Bool = false,
        listBullet: String = "-"
    ) {
        self.normalizeWhitespace = normalizeWhitespace
        self.includeLinkTargets = includeLinkTargets
        self.includePreformatAltText = includePreformatAltText
        self.listBullet = listBullet
    }
}

/// Markdown rendering options for ``GemtextRenderer/markdown(from:options:)``.
public struct GemtextMarkdownRenderOptions: Sendable {
    /// Collapses consecutive spaces/tabs and trims horizontal edge whitespace when `true`.
    public var normalizeWhitespace: Bool
    /// Maps preformat alt text to a Markdown code-fence info string when `true`.
    public var includePreformatAltTextAsInfoString: Bool
    /// Appends a closing fence when parsing ended inside preformatted mode.
    public var closeUnterminatedCodeFence: Bool
    
    /// Creates Markdown render options.
    public init(
        normalizeWhitespace: Bool = false,
        includePreformatAltTextAsInfoString: Bool = false,
        closeUnterminatedCodeFence: Bool = true
    ) {
        self.normalizeWhitespace = normalizeWhitespace
        self.includePreformatAltTextAsInfoString = includePreformatAltTextAsInfoString
        self.closeUnterminatedCodeFence = closeUnterminatedCodeFence
    }
}
