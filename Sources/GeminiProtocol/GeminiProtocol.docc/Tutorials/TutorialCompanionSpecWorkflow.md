# Companion Spec Workflow

This guide combines ``GeminiRobotsParser`` and ``GeminiSubscriptionParser`` in one workflow.

## Goal

Evaluate crawl policy for a bot role, then parse a feed page into subscription entries.

## Step 1: Parse Robots And Evaluate Policy

```swift
import Foundation
import GeminiProtocol

let robotsText = """
User-agent: *
Disallow: /private

User-agent: indexer
Disallow: /search
"""

let robots = try GeminiRobotsParser.parse(
    robotsText,
    options: .init(mode: .permissive)
)

let canVisitSearch = robots.isPathAllowed(
    "/search/index.gmi",
    virtualUserAgents: [.indexer]
)
```

## Step 2: Parse A Subscription Feed

```swift
let feedSource = """
# Example Gemlog
## Recent Posts
=> first.gmi 2026-02-17 - First post
=> second.gmi 2026-02-18 Second post
"""

let feedURL = URL(string: "gemini://example.org/gemlog/")!
let feed = try GeminiSubscriptionParser.parse(
    feedSource,
    feedURL: feedURL,
    options: .init(mode: .permissive)
)
```

## Step 3: Consume Entries

```swift
for entry in feed.entries {
    print(entry.updated, entry.title, entry.link.absoluteString)
}
```

## Step 4: Enforce Strict Parsing (Optional)

```swift
let strictRobots = try GeminiRobotsParser.parse(
    robotsText,
    options: .init(mode: .strict)
)

let strictFeed = try GeminiSubscriptionParser.parse(
    feedSource,
    feedURL: feedURL,
    options: .init(mode: .strict)
)

_ = (strictRobots, strictFeed)
```

Use strict mode when malformed input should fail fast rather than return diagnostics.
