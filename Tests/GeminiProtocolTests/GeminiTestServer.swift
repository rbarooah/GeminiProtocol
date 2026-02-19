//
//  TestServer.swift
//
//
// Copyright © 2022 Izzy Fraimow. All rights reserved.
//

import Foundation
import Network
import GeminiProtocol

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    
    func run(_ block: () -> Void) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()
        
        block()
    }
}

/// A server for use in automated testing.
public actor GeminiTestServer {
    private let listener: NWListener
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.geminiprotocol.test-server", qos: .userInitiated)
    private var isStarted = false
    private var assignedPort: UInt16?
    private var responsePayload = Data()
    private var lastRequestLine: String?
    
    init() {
        guard
            let port = NWEndpoint.Port(rawValue: 0),
            let listener = try? NWListener(using: .tcp, on: port) else {
                preconditionFailure("Failed to initialize test listener")
        }
        self.listener = listener
    }
    
    func start(header: GeminiResponseHeader, body: String) async throws -> UInt16 {
        var payload = Data(String(geminiResponseHeader: header).utf8)
        payload.append(Data(body.utf8))
        return try await start(responsePayload: payload)
    }
    
    func start(rawResponse: Data) async throws -> UInt16 {
        try await start(responsePayload: rawResponse)
    }
    
    private func start(responsePayload: Data) async throws -> UInt16 {
        self.responsePayload = responsePayload
        self.lastRequestLine = nil
        
        listener.newConnectionHandler = { [weak self] newConnection in
            guard let self else {
                newConnection.cancel()
                return
            }
            
            Task {
                await self.handle(connection: newConnection)
            }
        }
        
        if isStarted, let assignedPort {
            return assignedPort
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate()
            
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let self, let rawPort = self.listener.port?.rawValue else {
                        gate.run {
                            continuation.resume(throwing: GeminiClientError.transactionError("Test server failed to bind to an ephemeral port"))
                        }
                        return
                    }
                    
                    Task {
                        await self.recordStarted(port: rawPort)
                    }
                    gate.run {
                        continuation.resume(returning: rawPort)
                    }
                case .failed(let error):
                    gate.run {
                        continuation.resume(throwing: error)
                    }
                case .cancelled, .setup, .waiting:
                    break
                @unknown default:
                    break
                }
            }
            
            listener.start(queue: queue)
        }
    }
    
    private func recordStarted(port: UInt16) {
        isStarted = true
        assignedPort = port
    }
    
    func stop() {
        listener.newConnectionHandler = nil
        listener.stateUpdateHandler = nil
        listener.cancel()
        isStarted = false
        assignedPort = nil
        
        connection?.cancel()
        connection = nil
    }
    
    func observedRequestLine() -> String? {
        lastRequestLine
    }
    
    private func handle(connection newConnection: NWConnection) async {
        guard connection == nil else {
            newConnection.cancel()
            return
        }
        
        connection = newConnection
        connection?.start(queue: queue)
        
        lastRequestLine = await receiveRequestLine()
        await send(responsePayload)
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        connection?.cancel()
        connection = nil
    }
    
    private func receiveRequestLine() async -> String? {
        await withCheckedContinuation { continuation in
            guard let connection else {
                continuation.resume(returning: nil)
                return
            }
            
            receiveRequestLine(connection: connection, accumulated: Data(), continuation: continuation)
        }
    }
    
    private nonisolated func receiveRequestLine(
        connection: NWConnection,
        accumulated: Data,
        continuation: CheckedContinuation<String?, Never>
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, isComplete, error in
            var buffer = accumulated
            if let data {
                buffer.append(data)
            }
            
            if let range = buffer.range(of: Data([0x0D, 0x0A])) {
                let lineData = buffer[..<range.lowerBound]
                continuation.resume(returning: String(data: lineData, encoding: .utf8))
                return
            }
            
            if isComplete || error != nil || buffer.count > 4096 {
                continuation.resume(returning: String(data: buffer, encoding: .utf8))
                return
            }
            
            self.receiveRequestLine(connection: connection, accumulated: buffer, continuation: continuation)
        }
    }
    
    private func send(_ data: Data) async {
        await withCheckedContinuation { continuation in
            guard let connection else {
                continuation.resume()
                return
            }
            
            connection.send(
                content: data,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed { _ in
                    continuation.resume()
                }
            )
        }
    }
}
