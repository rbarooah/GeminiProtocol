//
// GeminiNetwork.swift
//
//

import Foundation
import Network

/// TLS verification behavior used by ``GeminiClient``.
public enum GeminiTLSMode: Sendable, Equatable {
    /// Uses platform certificate validation.
    case systemTrust
    /// Disables certificate validation.
    ///
    /// - Important: This mode is intended for testing/debugging only.
    case insecureNoVerification
}

private final class ResponseResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(GeminiResponseHeader, Data?), Error>?
    private let onResolve: () -> Void
    
    init(
        continuation: CheckedContinuation<(GeminiResponseHeader, Data?), Error>,
        onResolve: @escaping () -> Void
    ) {
        self.continuation = continuation
        self.onResolve = onResolve
    }
    
    func resume(returning value: (GeminiResponseHeader, Data?)) {
        resolve(.success(value))
    }
    
    func resume(throwing error: Error) {
        resolve(.failure(error))
    }
    
    private func resolve(_ result: Result<(GeminiResponseHeader, Data?), Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        
        self.continuation = nil
        lock.unlock()
        
        onResolve()
        
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

/// A low-level Gemini network client backed by `Network.framework`.
public actor GeminiClient {
    private static let maxHeaderLength = 1024
    private static let receiveChunkSize = 64 * 1024
    
    private let connection: NWConnection
    private let request: GeminiRequest
    private let queue = DispatchQueue(label: "com.geminiprotocol.gemini-client")
    private var isInFlight = false
    
    /// Creates a Gemini client for a request.
    ///
    /// - Parameters:
    ///   - request: A URL request whose URL must use the `gemini` scheme.
    ///   - tlsMode: TLS verification mode for the connection.
    /// - Throws: ``GeminiClientError`` when the request URL is invalid for Gemini.
    public init(request: URLRequest, tlsMode: GeminiTLSMode = .systemTrust) throws {
        try self.init(request: request, debug: false, tlsMode: tlsMode)
    }
    
    internal init(request: URLRequest, debug: Bool = false, tlsMode: GeminiTLSMode = .systemTrust) throws {
        guard let url = request.url else { throw GeminiClientError.initializationError("No URL specified") }
        self.request = try GeminiRequest(url: url)
        guard self.request.data.count <= Self.maxHeaderLength else {
            throw GeminiClientError.initializationError("Request exceeds Gemini 1024-byte line limit")
        }
        
        guard let urlHost = request.url?.host else { throw GeminiClientError.initializationError("No host specified") }
        let host = NWEndpoint.Host(urlHost)
        
        let urlPort = request.url?.port.map(UInt16.init) ?? 1965
        guard let port = NWEndpoint.Port(rawValue: urlPort) else { throw GeminiClientError.initializationError("Invalid port") }
        
        let parameters = NWParameters.gemini(queue, debug: debug, tlsMode: tlsMode)
        self.connection = NWConnection(host: host, port: port, using: parameters)
    }
    
    /// Starts the request and waits for a Gemini response.
    ///
    /// - Parameter timeout: Request timeout in seconds.
    /// - Returns: A tuple of parsed response header and optional response body.
    ///   For non-success status codes, the body value is `nil`.
    /// - Throws: ``GeminiClientError`` or lower-level networking errors.
    public func start(timeout: TimeInterval = 30) async throws -> (GeminiResponseHeader, Data?) {
        guard timeout > 0 else {
            throw GeminiClientError.initializationError("Timeout must be greater than zero")
        }
        
        guard !isInFlight else {
            throw GeminiClientError.transactionError("A request is already in flight for this client")
        }
        
        isInFlight = true
        defer { isInFlight = false }
        
        let connection = self.connection
        let request = self.request
        let timeoutInterval = DispatchTimeInterval.milliseconds(max(1, Int(timeout * 1000)))
        
        return try await withCheckedThrowingContinuation { continuation in
            let resolver = ResponseResolver(continuation: continuation) {
                connection.stateUpdateHandler = nil
                connection.cancel()
            }
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .waiting(let error):
                    resolver.resume(throwing: error)
                case .ready:
                    connection.send(
                        content: request.data,
                        isComplete: true,
                        completion: .contentProcessed { error in
                            if let error = error {
                                resolver.resume(throwing: error)
                            }
                        }
                    )
                case .failed(let error):
                    resolver.resume(throwing: error)
                case .cancelled:
                    resolver.resume(throwing: GeminiClientError.cancelled)
                case .setup, .preparing:
                    fallthrough
                @unknown default:
                    break
                }
            }
            
            GeminiClient.setupReceive(connection: connection, resolver: resolver, data: Data())
            
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeoutInterval) {
                resolver.resume(throwing: GeminiClientError.timeout(timeout))
            }
        }
    }
    
    /// Stops any in-flight request and closes the underlying connection.
    public func stop() {
        isInFlight = false
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
    
    private nonisolated static func setupReceive(connection: NWConnection, resolver: ResponseResolver, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: receiveChunkSize) { chunk, _, isComplete, error in
            var accumulated = data
            if let chunk {
                accumulated.append(chunk)
            }
            
            if let receiveError = error {
                do {
                    let result = try parseResponse(accumulated)
                    resolver.resume(returning: result)
                } catch {
                    resolver.resume(throwing: receiveError)
                }
                return
            }
            
            if Self.headerRange(in: accumulated) == nil, accumulated.count > maxHeaderLength {
                resolver.resume(throwing: GeminiClientError.transactionError("Invalid Gemini response - header exceeds 1024 bytes"))
                return
            }
            
            guard isComplete else {
                setupReceive(connection: connection, resolver: resolver, data: accumulated)
                return
            }
            
            do {
                let result = try parseResponse(accumulated)
                resolver.resume(returning: result)
            } catch {
                resolver.resume(throwing: error)
            }
        }
    }
    
    private nonisolated static func parseResponse(_ data: Data) throws -> (GeminiResponseHeader, Data?) {
        guard let headerRange = headerRange(in: data) else {
            throw GeminiClientError.transactionError("Invalid Gemini response - missing header delimiter")
        }
        
        let headerLength = data.distance(from: data.startIndex, to: headerRange.upperBound)
        guard headerLength <= maxHeaderLength else {
            throw GeminiClientError.transactionError("Invalid Gemini response - header exceeds 1024 bytes")
        }
        
        let headerBytes = data[..<headerRange.lowerBound]
        if headerBytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            throw GeminiClientError.transactionError("Invalid Gemini response - header begins with UTF-8 BOM")
        }
        guard let headerString = String(data: headerBytes, encoding: .utf8) else {
            throw GeminiClientError.transactionError("Invalid Gemini response - header is not UTF-8")
        }
        
        guard headerString.count >= 2 else {
            throw GeminiClientError.transactionError("Invalid Gemini response - malformed header")
        }
        
        let statusDigits = String(headerString.prefix(2))
        guard
            let statusValue = Int(statusDigits),
            let status = GeminiStatusCode.fromProtocolValue(statusValue) else {
                throw GeminiClientError.transactionError("Invalid Gemini response - status code is not valid")
        }
        
        let statusEnd = headerString.index(headerString.startIndex, offsetBy: 2)
        let suffix = headerString[statusEnd...]
        
        let meta: String
        if suffix.isEmpty {
            if status.requiresMeta {
                throw GeminiClientError.transactionError("Invalid Gemini response - missing required meta")
            }
            meta = ""
        } else {
            guard suffix.first == " " else {
                throw GeminiClientError.transactionError("Invalid Gemini response - missing status separator")
            }
            meta = String(suffix.dropFirst())
            if meta.isEmpty {
                throw GeminiClientError.transactionError("Invalid Gemini response - empty meta after separator")
            }
        }
        
        let header = GeminiResponseHeader(status: status, meta: meta)
        
        let bodySlice = data[headerRange.upperBound...]
        let body = bodySlice.isEmpty ? Data() : Data(bodySlice)
        return (header, status.isSuccess ? body : nil)
    }
    
    private nonisolated static func headerRange(in data: Data) -> Range<Data.Index>? {
        guard data.count >= 2 else { return nil }
        
        var index = data.startIndex
        let end = data.index(before: data.endIndex)
        
        while index < end {
            let nextIndex = data.index(after: index)
            if data[index] == 0x0d, data[nextIndex] == 0x0a {
                return index..<data.index(after: nextIndex)
            }
            index = nextIndex
        }
        
        return nil
    }
}

extension NWParameters {
    static func gemini(_ queue: DispatchQueue, debug: Bool = false, tlsMode: GeminiTLSMode = .systemTrust) -> NWParameters {
        let parameters: NWParameters
        if debug {
            parameters = .tcp
        } else {
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
            if tlsMode == .insecureNoVerification {
                sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, _, secProtocolVerifyComplete in
                    secProtocolVerifyComplete(true)
                }, queue)
            }
            
            let tcpOptions = NWProtocolTCP.Options()
            parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        }
        
        return parameters
    }
}
