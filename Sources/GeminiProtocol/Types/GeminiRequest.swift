//
// GeminiRequest.swift
//
//

import Foundation

/// Canonical Gemini request line representation used by the network client.
public struct GeminiRequest: Sendable {
    let absoluteURI: String
    
    var data: Data {
        Data("\(absoluteURI)\r\n".utf8)
    }
    
    init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GeminiClientError.initializationError("Could not parse URL components")
        }
        
        guard components.user == nil, components.password == nil else {
            throw GeminiClientError.initializationError("User info is not allowed in Gemini URLs")
        }
        
        guard components.scheme?.lowercased() == "gemini" else {
            throw GeminiClientError.initializationError("URL scheme must be gemini")
        }
        
        var normalized = components
        normalized.fragment = nil
        if normalized.path.isEmpty {
            normalized.path = "/"
        }
        
        guard let normalizedURL = normalized.url else {
            throw GeminiClientError.initializationError("Could not normalize Gemini URL")
        }
        
        self.absoluteURI = normalizedURL.absoluteString
    }
}
