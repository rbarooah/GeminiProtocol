# Using GeminiClient

Use ``GeminiClient`` for direct async Gemini transactions without `URLSession`.

## Create The Client

```swift
import Foundation
import GeminiProtocol

let request = URLRequest(url: URL(string: "gemini://geminiprotocol.net/")!)
let client = try GeminiClient(request: request)
```

`GeminiClient` defaults to ``GeminiTLSMode/systemTrust``.

For debugging environments, you can opt out of certificate verification:

```swift
let insecureClient = try GeminiClient(
    request: request,
    tlsMode: .insecureNoVerification
)
```

## Start A Transaction

```swift
let (header, maybeBody) = try await client.start(timeout: 20)

switch header.status {
case .success:
    let body = maybeBody ?? Data()
    print("meta=\(header.meta), bytes=\(body.count)")
default:
    print("status=\(header.status.rawValue), meta=\(header.meta)")
}
```

`start(timeout:)` returns:

- Parsed ``GeminiResponseHeader``.
- `Data?` body where body is non-`nil` only for success responses.

## Error Handling

`GeminiClient` may throw:

- ``GeminiClientError`` values for initialization/timeout/transaction issues.
- Lower-level `Network.framework` errors surfaced during connection attempts.

If needed, cancel and close resources with ``GeminiClient/stop()``.
