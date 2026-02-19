# GeminiProtocol

`Network.Framework` and `URLSession` support for the Gemini protocol.

This module is intended as an implementation of the Gemini protocol specification:
[https://geminiprotocol.net/docs/protocol-specification.gmi](https://geminiprotocol.net/docs/protocol-specification.gmi)

## Attribution

This codebase began as a clone/fork of the original project at [frozendevil/GeminiProtocol](https://github.com/frozendevil/GeminiProtocol).

Subsequent updates in this repository were developed by GPT-3.5 Codex supervised by Robin Barooah.

## Usage

### URLSession
Calling `URLProtocol.registerClass(GeminiProtocol.self)` will cause your normal `URLSession` code to "Just Work" with `gemini://` URLs. The `URLResponse` you receive will be a `GeminiURLResponse` with `statusCode` and `meta` properties.

### Network Client
Use `GeminiClient` directly for lower-level requests:

```swift
let request = URLRequest(url: URL(string: "gemini://gemini.circumlunar.space/")!)
let client = try GeminiClient(request: request)
let (header, body) = try await client.start(timeout: 20)
```

`GeminiClient` uses system TLS trust by default. If you need insecure certificate acceptance for debugging only, use:

```swift
let client = try GeminiClient(request: request, tlsMode: .insecureNoVerification)
```

### Gemtext Parsing
Parse `text/gemini` documents into a typed AST with diagnostics:

```swift
let options = GemtextParserOptions(
    mode: .permissive,
    baseURL: URL(string: "gemini://example.org/")!
)
let document = try GemtextParser.parse(gemtextString, options: options)
```

Renderer helpers are also available for normalization to plain text and Markdown:

```swift
let plain = GemtextRenderer.plainText(
    from: document,
    options: .init(normalizeWhitespace: true)
)
let markdown = GemtextRenderer.markdown(
    from: document,
    options: .init(normalizeWhitespace: true, includePreformatAltTextAsInfoString: true)
)
```

### Companion Specification Parsing
Parse both currently published companion specifications from [https://geminiprotocol.net/docs/companion/](https://geminiprotocol.net/docs/companion/) (`robots.txt` and lightweight subscription feeds):

```swift
let robots = try GeminiRobotsParser.parse(robotsText)
let disallowedForIndexer = robots.disallowPrefixes(for: [.indexer])

let feedURL = URL(string: "gemini://example.org/gemlog/")!
let feed = try GeminiSubscriptionParser.parse(gemtextFeedPage, feedURL: feedURL)
```

## Code
- `GeminiProtocol.swift` contains the implementation of the `URLSession` support.
- `GeminiNetwork.swift` is a `Network.framework` implementation of a Gemini client.
- `GemtextParser.swift` and `GemtextTypes.swift` implement a line-oriented parser for `text/gemini`.
- `GemtextRenderer.swift` provides plain-text and Markdown normalization helpers.
- `CompanionParsers.swift` and `CompanionTypes.swift` implement companion-spec parsing helpers.

## Conformance
- Request URIs are normalized to match spec requirements:
  - userinfo is rejected
  - fragments are omitted
  - empty paths are normalized to `/`
  - request line length is capped at 1024 bytes
- Response parsing enforces key protocol constraints:
  - UTF-8 headers with mandatory CRLF delimiter
  - UTF-8 BOM at header start is rejected
  - status codes outside `10...69` are rejected
  - undefined status codes in `10...69` are handled by class fallback (`1x`, `2x`, etc.)
  - optional meta for `4x`, `5x`, `6x` is supported
  - required meta for `1x`, `2x`, `3x` is enforced
- TLS 1.2+ is required by default.

### Known Variances
- MIME type grammar for `2x` responses is not fully validated; the header meta is exposed as-is.
- Redirect-following policy (including 5-hop limit) is intentionally not implemented in the low-level client; callers decide redirect behavior.
- Automatic client-certificate flows for `6x` responses are not implemented by this library.
- Robots parser intentionally ignores non-core robots extensions (e.g. `Allow`, crawl-delay, wildcard matching); only comment, `User-agent`, and `Disallow` directives are interpreted.
- In permissive mode, subscription feeds missing a level-1 heading use the feed URL as a fallback title and surface a diagnostic; strict mode rejects them.
- Subscription parser title sanitization after a date prefix uses conservative heuristics and may differ from client-specific presentation choices.

## Testing
- `swift test` runs local tests.
- `GEMINI_LIVE_TESTS=1 swift test` also runs internet-backed tests against multiple public Gemini capsules.

## Documentation
Build the DocC archive locally from the package root:

```bash
swift package dump-symbol-graph
docc convert Sources/GeminiProtocol/GeminiProtocol.docc \
  --fallback-display-name GeminiProtocol \
  --fallback-bundle-identifier com.example.GeminiProtocol \
  --fallback-bundle-version 1.0.0 \
  --additional-symbol-graph-dir .build/arm64-apple-macosx/symbolgraph \
  --output-path .build/docc/GeminiProtocol.doccarchive
```
