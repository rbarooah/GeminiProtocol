//
// GeminiProtocol.swift
//
//

import Foundation
import Network
import os.log

/// `URLProtocol` implementation that enables `URLSession` support for `gemini://` URLs.
public class GeminiProtocol: URLProtocol, @unchecked Sendable {
    static let logger = Logger(subsystem: "com.izzy.computer", category: "Protocol")
    nonisolated(unsafe) static var usePlaintextTransport = false
    
    private var loadingTask: Task<Void, Never>?
    
    enum ProtocolError: Error {
        case taskError(String)
    }
    
    /// Returns `true` when the request URL uses the `gemini` scheme.
    public override class func canInit(with request: URLRequest) -> Bool {
        Self.logger.debug("Triaging request: \(request)")
        
        guard let url = request.url, let scheme = url.scheme else { return false }
        let normalizedScheme = scheme.lowercased()
        guard normalizedScheme == "gemini" else { return false }
        
        Self.logger.debug("Accepted request: \(request)")
        return true
    }
    
    /// Returns `true` when the task's current request can be handled as Gemini.
    public override class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest else { return false }
        return canInit(with: request)
    }
    
    /// Returns the canonical form of a request.
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    
    /// Begins loading the Gemini request.
    public override func startLoading() {
        let request = self.request
        let protocolReference: URLProtocol = self
        guard let urlProtocolClient = self.client else {
            Self.logger.error("URLProtocol client missing for request: \(request)")
            return
        }
        let usePlaintextTransport = Self.usePlaintextTransport
        
        loadingTask = Task {
            var connection: GeminiClient?
            
            do {
                let createdConnection = try GeminiClient(request: request, debug: usePlaintextTransport)
                connection = createdConnection
                
                let (header, maybeData) = try await withTaskCancellationHandler(operation: {
                    try await createdConnection.start()
                }, onCancel: {
                    Task {
                        await createdConnection.stop()
                    }
                })
                
                guard let url = request.url else {
                    throw ProtocolError.taskError("URL missing from URLRequest")
                }
                
                let data = maybeData ?? Data()
                let response = GeminiURLResponse(
                    url: url,
                    expectedContentLength: data.count,
                    statusCode: header.status,
                    meta: header.meta
                )
                
                urlProtocolClient.urlProtocol(protocolReference, didReceive: response, cacheStoragePolicy: .notAllowed)
                urlProtocolClient.urlProtocol(protocolReference, didLoad: data)
                urlProtocolClient.urlProtocolDidFinishLoading(protocolReference)
            } catch is CancellationError {
                await connection?.stop()
            } catch {
                await connection?.stop()
                urlProtocolClient.urlProtocol(protocolReference, didFailWithError: error)
            }
        }
    }
    
    /// Stops loading and cancels any in-flight task.
    public override func stopLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }
}
