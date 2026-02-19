//
// GemtextRenderer.swift
//
//

import Foundation

/// Helper renderers for converting parsed gemtext to normalized output formats.
public enum GemtextRenderer {
    /// Renders a ``GemtextDocument`` to plain text.
    ///
    /// - Parameters:
    ///   - document: Parsed gemtext document.
    ///   - options: Plain text rendering options.
    /// - Returns: Normalized plain text output.
    public static func plainText(
        from document: GemtextDocument,
        options: GemtextPlainTextRenderOptions = .init()
    ) -> String {
        var rendered: [String] = []
        
        for line in document.lines {
            switch line {
            case .text(let textLine):
                rendered.append(normalize(textLine.text, enabled: options.normalizeWhitespace && !textLine.isPreformatted))
            case .link(let linkLine):
                rendered.append(renderPlainTextLink(linkLine, options: options))
            case .heading(let headingLine):
                rendered.append(normalize(headingLine.text, enabled: options.normalizeWhitespace))
            case .listItem(let itemLine):
                let content = normalize(itemLine.text, enabled: options.normalizeWhitespace)
                rendered.append("\(options.listBullet) \(content)")
            case .quote(let quoteLine):
                let content = normalize(quoteLine.text, enabled: options.normalizeWhitespace)
                rendered.append(">\(content)")
            case .preformatToggle(let toggleLine):
                if options.includePreformatAltText, toggleLine.entersPreformatted {
                    let alt = trimHorizontalWhitespace(toggleLine.altText)
                    if !alt.isEmpty {
                        rendered.append("[\(alt)]")
                    }
                }
            }
        }
        
        return rendered.joined(separator: "\n")
    }
    
    /// Renders a ``GemtextDocument`` to Markdown.
    ///
    /// - Parameters:
    ///   - document: Parsed gemtext document.
    ///   - options: Markdown rendering options.
    /// - Returns: Markdown output derived from gemtext line semantics.
    public static func markdown(
        from document: GemtextDocument,
        options: GemtextMarkdownRenderOptions = .init()
    ) -> String {
        var rendered: [String] = []
        var inCodeBlock = false
        
        for line in document.lines {
            switch line {
            case .text(let textLine):
                if textLine.isPreformatted {
                    rendered.append(textLine.raw)
                } else {
                    rendered.append(normalize(textLine.text, enabled: options.normalizeWhitespace))
                }
            case .link(let linkLine):
                rendered.append(renderMarkdownLink(linkLine, normalizeWhitespace: options.normalizeWhitespace))
            case .heading(let headingLine):
                let headingText = normalize(headingLine.text, enabled: options.normalizeWhitespace)
                rendered.append("\(String(repeating: "#", count: max(1, min(headingLine.level, 6)))) \(headingText)")
            case .listItem(let itemLine):
                let content = normalize(itemLine.text, enabled: options.normalizeWhitespace)
                rendered.append("- \(content)")
            case .quote(let quoteLine):
                let content = normalize(quoteLine.text, enabled: options.normalizeWhitespace)
                rendered.append(">\(content)")
            case .preformatToggle(let toggleLine):
                if toggleLine.entersPreformatted {
                    inCodeBlock = true
                    if options.includePreformatAltTextAsInfoString {
                        let infoString = sanitizeCodeFenceInfoString(toggleLine.altText)
                        if infoString.isEmpty {
                            rendered.append("```")
                        } else {
                            rendered.append("``` \(infoString)")
                        }
                    } else {
                        rendered.append("```")
                    }
                } else {
                    inCodeBlock = false
                    rendered.append("```")
                }
            }
        }
        
        if inCodeBlock, options.closeUnterminatedCodeFence {
            rendered.append("```")
        }
        
        return rendered.joined(separator: "\n")
    }
    
    private static func renderPlainTextLink(_ line: GemtextLinkLine, options: GemtextPlainTextRenderOptions) -> String {
        let label = line.label.map { normalize($0, enabled: options.normalizeWhitespace) }
        if options.includeLinkTargets {
            if let label {
                return "\(label) (\(line.target))"
            }
            return line.target
        }
        
        return label ?? line.target
    }
    
    private static func renderMarkdownLink(_ line: GemtextLinkLine, normalizeWhitespace: Bool) -> String {
        if let label = line.label, !label.isEmpty {
            let normalizedLabel = normalize(label, enabled: normalizeWhitespace)
            return "[\(escapeMarkdownLabel(normalizedLabel))](\(line.target))"
        }
        return "<\(line.target)>"
    }
    
    private static func normalize(_ value: String, enabled: Bool) -> String {
        guard enabled else { return value }
        
        var output = ""
        var wasWhitespace = false
        for character in value {
            if character == " " || character == "\t" {
                if !wasWhitespace {
                    output.append(" ")
                    wasWhitespace = true
                }
            } else {
                output.append(character)
                wasWhitespace = false
            }
        }
        
        return trimHorizontalWhitespace(output)
    }
    
    private static func trimHorizontalWhitespace(_ value: String) -> String {
        let leadingTrimmed = value.drop { $0 == " " || $0 == "\t" }
        let trailingTrimmed = leadingTrimmed.reversed().drop { $0 == " " || $0 == "\t" }
        return String(trailingTrimmed.reversed())
    }
    
    private static func sanitizeCodeFenceInfoString(_ value: String) -> String {
        trimHorizontalWhitespace(value).replacingOccurrences(of: "`", with: "")
    }
    
    private static func escapeMarkdownLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}
