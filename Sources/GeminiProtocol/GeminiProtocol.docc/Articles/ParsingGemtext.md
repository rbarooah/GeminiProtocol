# Parsing Gemtext

Parse Gemtext source into typed line nodes and optional diagnostics with ``GemtextParser``.

## Parse Source

```swift
import Foundation
import GeminiProtocol

let source = """
# Capsule Home
=> /posts First post
"""

let options = GemtextParserOptions(
    mode: .permissive,
    baseURL: URL(string: "gemini://example.org/")
)

let document = try GemtextParser.parse(source, options: options)
print(document.lines.count)
print(document.diagnostics.count)
```

Use ``GemtextParserMode/permissive`` to collect diagnostics and continue parsing. Use ``GemtextParserMode/strict`` when parse errors should fail immediately.

## Work With Typed Lines

The parser emits a ``GemtextLine`` enum with dedicated payload types:

- ``GemtextTextLine``
- ``GemtextLinkLine``
- ``GemtextHeadingLine``
- ``GemtextListItemLine``
- ``GemtextQuoteLine``
- ``GemtextPreformatToggleLine``

Each node includes the raw source line and line number.

## Render Normalized Output

Convert parsed documents into plain text or Markdown:

```swift
let plain = GemtextRenderer.plainText(
    from: document,
    options: .init(normalizeWhitespace: true)
)

let markdown = GemtextRenderer.markdown(
    from: document,
    options: .init(
        normalizeWhitespace: true,
        includePreformatAltTextAsInfoString: true
    )
)
```

Rendering options are controlled by ``GemtextPlainTextRenderOptions`` and ``GemtextMarkdownRenderOptions``.
