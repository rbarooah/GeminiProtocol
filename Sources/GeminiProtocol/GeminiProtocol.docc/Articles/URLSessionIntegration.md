# URLSession Integration

Use ``GeminiProtocol`` when you want existing `URLSession` call sites to handle Gemini URLs.

## Register The Protocol

Register the protocol class before creating sessions that should handle `gemini://` requests:

```swift
import Foundation
import GeminiProtocol

URLProtocol.registerClass(GeminiProtocol.self)
```

For explicit control, create a dedicated session configuration:

```swift
let configuration = URLSessionConfiguration.ephemeral
configuration.protocolClasses = [GeminiProtocol.self]
let session = URLSession(configuration: configuration)
```

## Make A Request

```swift
let url = URL(string: "gemini://geminiprotocol.net/")!
let (data, response) = try await session.data(from: url)

guard let geminiResponse = response as? GeminiURLResponse else {
    throw URLError(.badServerResponse)
}

print(geminiResponse.statusCode)
print(geminiResponse.meta)
print(data.count)
```

## Interpret Response Fields

- ``GeminiURLResponse/statusCode`` contains Gemini status semantics.
- ``GeminiURLResponse/meta`` contains the raw Gemini meta field.
- ``GeminiURLResponse/mimeType`` is populated only for success responses.

For non-success statuses, Gemini bodies are not surfaced by this module and response data is empty.
