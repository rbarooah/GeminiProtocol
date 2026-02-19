# Build A Gemini Fetcher

This guide walks through a small production-style fetch path using ``GeminiClient``.

## Goal

Fetch one Gemini URL, branch on status, and decode body bytes when available.

## Step 1: Build The Request

```swift
import Foundation
import GeminiProtocol

let url = URL(string: "gemini://geminiprotocol.net/")!
let request = URLRequest(url: url)
```

## Step 2: Initialize The Client

```swift
let client = try GeminiClient(request: request, tlsMode: .systemTrust)
```

If your environment requires temporary trust bypass for diagnostics, use `.insecureNoVerification`.

## Step 3: Start And Handle The Response

```swift
let (header, maybeBody) = try await client.start(timeout: 20)

if header.status.isSuccess {
    let body = maybeBody ?? Data()
    let text = String(data: body, encoding: .utf8)
    print("success: \(header.meta)")
    print(text ?? "<non-utf8 body>")
} else {
    print("non-success: \(header.status.rawValue) \(header.meta)")
}
```

## Step 4: Add Error Handling

```swift
do {
    let (header, body) = try await client.start(timeout: 20)
    print(header.status, body?.count ?? 0)
} catch let error as GeminiClientError {
    print("Gemini client error: \(error.localizedDescription)")
} catch {
    print("Unexpected error: \(error)")
}
```

This is the core transaction flow used by higher-level wrappers.
