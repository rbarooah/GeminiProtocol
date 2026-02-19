//
// GeminiResponseHeader.swift
//
//

/// Parsed Gemini response header fields.
public struct GeminiResponseHeader: Equatable, Sendable {
    /// Gemini status code.
    public let status: GeminiStatusCode
    /// Gemini meta value (MIME type, redirect target, prompt, or error text depending on status).
    public let meta: String

    /// Creates a response header value.
    ///
    /// - Parameters:
    ///   - status: Gemini status code.
    ///   - meta: Meta field string.
    public init(status: GeminiStatusCode, meta: String) {
        self.status = status
        self.meta = meta
    }
}

extension String {
    /// Creates a serialized Gemini response header line (`<status> <meta>\r\n`).
    public init(geminiResponseHeader: GeminiResponseHeader) {
        self.init("\(geminiResponseHeader.status.rawValue) \(geminiResponseHeader.meta)\r\n")
    }
}
