//
// GeminiStatusCode.swift
//
//

/// Gemini response status codes defined by the protocol.
public enum GeminiStatusCode: Int, RawRepresentable, Sendable {
    /// `10`: input required.
    case input = 10
    /// `11`: sensitive input required.
    case sensitiveInput
    
    /// `20`: successful response.
    case success = 20
    
    /// `30`: temporary redirect.
    case redirectTemporary = 30
    /// `31`: permanent redirect.
    case redirectPermanent
    
    /// `40`: temporary failure.
    case temporaryFailure = 40
    /// `41`: server unavailable.
    case serverUnavailable
    /// `42`: CGI error.
    case cgiError
    /// `43`: proxy error.
    case proxyError
    /// `44`: slow down.
    case slowDown
    
    /// `50`: permanent failure.
    case permanentFailure = 50
    /// `51`: not found.
    case notFound
    /// `52`: gone.
    case gone
    /// `53`: proxy request refused.
    case proxyRequestRefused
    /// `54`: bad request.
    case badRequest
    
    /// `60`: client certificate required.
    case clientCertificateRequired = 60
    /// `61`: certificate not authorized.
    case certificateNotAuthorized
    /// `62`: certificate not valid.
    case certificateNotValid
    
    /// Indicates whether the status represents a successful response (`20` class).
    public var isSuccess: Bool {
        self == .success
    }
}

extension GeminiStatusCode {
    static func fromProtocolValue(_ value: Int) -> GeminiStatusCode? {
        guard (10...69).contains(value) else { return nil }
        if let known = GeminiStatusCode(rawValue: value) {
            return known
        }
        
        switch value / 10 {
        case 1:
            return .input
        case 2:
            return .success
        case 3:
            return .redirectTemporary
        case 4:
            return .temporaryFailure
        case 5:
            return .permanentFailure
        case 6:
            return .clientCertificateRequired
        default:
            return nil
        }
    }
    
    var categoryDigit: Int {
        rawValue / 10
    }
    
    var requiresMeta: Bool {
        categoryDigit <= 3
    }
}
