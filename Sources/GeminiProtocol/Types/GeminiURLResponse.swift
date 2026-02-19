//
// GeminiURLResponse.swift
//
//

import Foundation

private let StatusCodeKey = "StatusCodeKey"
private let MetaKey = "MetaKey"

/// `URLResponse` subclass carrying Gemini-specific response fields.
public final class GeminiURLResponse: URLResponse, @unchecked Sendable {
    /// Gemini status code.
    public let statusCode: GeminiStatusCode
    /// Raw Gemini meta string.
    public let meta: String
    
    /// Indicates support for secure coding.
    class public override var supportsSecureCoding: Bool {
        true
    }
    
    /// MIME type for successful responses, otherwise `nil`.
    public override var mimeType: String? {
        statusCode.isSuccess ? meta : nil
    }
    
    /// Creates a Gemini URL response.
    ///
    /// - Parameters:
    ///   - url: Request URL.
    ///   - expectedContentLength: Expected body length.
    ///   - statusCode: Gemini status code.
    ///   - meta: Gemini meta value.
    public init(url: URL, expectedContentLength: Int, statusCode: GeminiStatusCode, meta: String) {
        self.statusCode = statusCode
        self.meta = meta
        
        let mimeType = statusCode.isSuccess ? meta : nil
        super.init(url: url, mimeType: mimeType, expectedContentLength: expectedContentLength, textEncodingName: nil)
    }
    
    required init(_ response: GeminiURLResponse) {
        self.statusCode = response.statusCode
        self.meta = response.meta
        
        super.init(
            url: response.url!,
            mimeType: response.mimeType,
            expectedContentLength: Int(response.expectedContentLength),
            textEncodingName: response.textEncodingName
        )
    }
    
    required init?(coder: NSCoder) {
        let statusCodeValue = coder.decodeInteger(forKey: StatusCodeKey)
        guard let statusCode = GeminiStatusCode(rawValue: statusCodeValue) else {
            return nil
        }
        self.statusCode = statusCode
        
        guard let meta = coder.decodeObject(of: NSString.self, forKey: MetaKey) as String? else {
            return nil
        }
        self.meta = meta
        
        super.init(coder: coder)
    }
    
    /// Encodes Gemini-specific fields for secure archiving.
    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        
        coder.encode(statusCode.rawValue, forKey: StatusCodeKey)
        coder.encode(meta, forKey: MetaKey)
    }
    
    /// Returns a copy of this response.
    override public func copy() -> Any {
        return type(of:self).init(self)
    }
    
    /// Returns a copy of this response.
    override public func copy(with zone: NSZone? = nil) -> Any {
        return type(of:self).init(self)
    }
}
