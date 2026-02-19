# Parsing Companion Specifications

This module includes parsers for both currently published companion specs:

- Gemini `robots.txt` convention
- Gemtext subscription-feed convention

## Parse Robots Policy

```swift
import GeminiProtocol

let robotsText = """
User-agent: *
Disallow: /private

User-agent: indexer
Disallow: /search
"""

let policy = try GeminiRobotsParser.parse(robotsText)
let prefixes = policy.disallowPrefixes(for: [.indexer])
let allowed = policy.isPathAllowed("/search/posts.gmi", virtualUserAgents: [.indexer])
```

`GeminiRobotsParser` supports permissive and strict modes via ``GeminiRobotsParserOptions``.

## Parse Subscription Feed

```swift
import Foundation
import GeminiProtocol

let feedSource = """
# Example Gemlog
## Recent Posts
=> first.gmi 2026-02-17 - First post
=> second.gmi 2026-02-18 Second post
"""

let feedURL = URL(string: "gemini://example.org/gemlog/")!
let feed = try GeminiSubscriptionParser.parse(feedSource, feedURL: feedURL)

print(feed.title)
print(feed.entries.count)
print(feed.updated)
```

`GeminiSubscriptionParser` extracts entries from dated link labels and computes feed `updated` from the newest extracted entry.

## Diagnostics And Strict Mode

Both companion parsers surface `GemtextDiagnostic` values and support strict mode:

- ``GeminiRobotsParserError/strictModeViolation(_:)``
- ``GeminiSubscriptionParserError/strictModeViolation(_:)``

Use strict mode when invalid companion data should fail parsing.
