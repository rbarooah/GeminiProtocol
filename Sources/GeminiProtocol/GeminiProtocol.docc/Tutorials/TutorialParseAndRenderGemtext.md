# Parse And Render Gemtext

This guide shows a full parse-to-render pipeline using ``GemtextParser`` and ``GemtextRenderer``.

## Goal

Convert source Gemtext into typed nodes, inspect diagnostics, and produce normalized plain text and Markdown.

## Step 1: Parse Input

````swift
import Foundation
import GeminiProtocol

let source = """
# Gemini Title
=> /docs/spec.gmi Protocol specification
* List item text
```swift
let x = 1
```
"""

let document = try GemtextParser.parse(
    source,
    options: .init(
        mode: .permissive,
        baseURL: URL(string: "gemini://example.org/")
    )
)
````

## Step 2: Inspect Nodes

```swift
for line in document.lines {
    switch line {
    case .heading(let heading):
        print("heading(\(heading.level)): \(heading.text)")
    case .link(let link):
        print("link: \(link.target) -> \(link.resolvedURL?.absoluteString ?? "unresolved")")
    default:
        break
    }
}
```

## Step 3: Review Diagnostics

```swift
for diagnostic in document.diagnostics {
    print("line \(diagnostic.line): \(diagnostic.severity.rawValue) \(diagnostic.message)")
}
```

Switch to strict mode when diagnostics with severity `error` should throw.

## Step 4: Render Output

```swift
let plain = GemtextRenderer.plainText(
    from: document,
    options: .init(normalizeWhitespace: true, includeLinkTargets: true)
)

let markdown = GemtextRenderer.markdown(
    from: document,
    options: .init(normalizeWhitespace: true, includePreformatAltTextAsInfoString: true)
)
```

Use this pattern when you need structured parsing plus normalized export formats.
