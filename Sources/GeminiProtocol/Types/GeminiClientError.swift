//
// GeminiClientError.swift
//
//

import Foundation

/// Errors produced by ``GeminiClient``.
public enum GeminiClientError: Error {
    /// The request or client setup was invalid.
    case initializationError(String)
    /// A protocol or transport error occurred while processing the transaction.
    case transactionError(String)
    /// The request was cancelled.
    case cancelled
    /// The request timed out after the supplied interval.
    case timeout(TimeInterval)
}

extension GeminiClientError: LocalizedError {
    /// Localized description suitable for logs and user-facing error surfaces.
    public var errorDescription: String? {
        switch self {
        case .initializationError(let reason):
            return "Gemini client initialization failed: \(reason)"
        case .transactionError(let reason):
            return "Gemini transaction failed: \(reason)"
        case .cancelled:
            return "Gemini request was cancelled."
        case .timeout(let interval):
            return "Gemini request timed out after \(interval) seconds."
        }
    }
}
