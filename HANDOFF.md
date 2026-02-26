# GeminiProtocol Hand-off

Last updated: 2026-02-26 00:00:30Z (UTC)

## Repository Status

- Branch: `main`
- Primary push target used: `fork` (`git@github.com:rbarooah/GeminiProtocol.git`)
- Upstream remote: `origin` (`git@github.com:frozendevil/GeminiProtocol.git`)
- Current head before this hand-off doc: `3be933c`

## What Is In Place

### Protocol and Client

- Gemini request normalization and response parsing conformance hardening is in place.
- `GeminiClient` supports:
  - system trust TLS (`.systemTrust`)
  - insecure no-verification mode (`.insecureNoVerification`) for debugging
- `GeminiProtocol` (`URLProtocol` integration) now has logging disabled by default:
  - `GeminiProtocol.isLoggingEnabled = false`
  - This addresses noisy output reports.

### Gemtext and Companion Specs

Implemented and tested:

- Gemtext parser + typed AST:
  - `Sources/GeminiProtocol/GemtextParser.swift`
  - `Sources/GeminiProtocol/GemtextTypes.swift`
- Rendering helpers:
  - `Sources/GeminiProtocol/GemtextRenderer.swift`
- Companion parsers:
  - `Sources/GeminiProtocol/CompanionParsers.swift`
  - `Sources/GeminiProtocol/CompanionTypes.swift`

Companion specs covered:

- robots.txt for Gemini
- subscription feed convention

### Documentation

- Public API DocC comments added across consumer-facing APIs.
- Full DocC catalog added at:
  - `Sources/GeminiProtocol/GeminiProtocol.docc/`
- README includes:
  - protocol spec link
  - companion parsing usage
  - DocC build instructions
  - attribution and tooling note requested in prior steps

### Example Executable

Added executable target:

- `AntennaMirrorExample`
- Source: `Sources/AntennaMirrorExample/main.swift`

Behavior:

- Fetches front page: `gemini://warmedal.se/~antenna/`
- Extracts linked Gemini URLs
- Fetches linked resources
- Converts responses to Markdown
- Writes local output folder with:
  - `front-page.md`
  - `index.md`
  - `articles/*.md`

## One-time Output Requested Previously

Completed previously as requested:

- Mirror run to: `/tmp/AntennaMirrorOutput`
- Markdown-to-PDF conversion of generated output completed (47 PDFs)

## Key Recent Commits

- `3be933c` Disable GeminiProtocol logging by default
- `c096e34` Add Antenna mirror example executable
- `27343f6` Update LICENSE with Robin Barooah copyright line
- `8c49fc2` Adjust README attribution wording
- `5720604` Implement gemtext and companion parsers with docs and conformance tests

## Run / Validation Commands

### Tests

```bash
swift test
```

Optional live internet-backed tests:

```bash
GEMINI_LIVE_TESTS=1 swift test --filter LiveGeminiSitesTests.testFetchesMultiplePublicGeminiCapsules
```

### Example CLI

```bash
swift run AntennaMirrorExample
```

Or custom output path:

```bash
swift run AntennaMirrorExample /tmp/AntennaMirrorOutput
```

### DocC Build

```bash
swift package dump-symbol-graph
docc convert Sources/GeminiProtocol/GeminiProtocol.docc \
  --fallback-display-name GeminiProtocol \
  --fallback-bundle-identifier com.example.GeminiProtocol \
  --fallback-bundle-version 1.0.0 \
  --additional-symbol-graph-dir .build/arm64-apple-macosx/symbolgraph \
  --output-path .build/docc/GeminiProtocol.doccarchive
```

## Known Caveats

- Live Gemini test relies on external capsule availability and certificate state.
- Example CLI does not currently follow redirects; redirect responses are recorded as failures.
- Example CLI uses permissive gemtext parsing and best-effort mirroring (captures failures instead of aborting).

## Immediate Next Work Items (if you continue now)

1. Add optional redirect-following to `AntennaMirrorExample` (bounded hop count).
2. Add optional concurrency limit to speed up article mirroring while avoiding overload.
3. Add optional font configuration for markdown->PDF workflows if full emoji/CJK coverage is required.
