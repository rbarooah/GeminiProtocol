# ``GeminiProtocol``

A Swift package for consuming Gemini resources via `URLSession`, a low-level async client, and parsers for Gemtext and companion specifications.

## Overview

Use this module when you need one or more of the following:

- `URLSession` access to `gemini://` URLs via ``GeminiProtocol`` and ``GeminiURLResponse``.
- Direct connection-level control via ``GeminiClient``.
- Parsing and rendering of `text/gemini` content via ``GemtextParser`` and ``GemtextRenderer``.
- Parsing of Gemini companion conventions via ``GeminiRobotsParser`` and ``GeminiSubscriptionParser``.

## Topics

### Networking

- <doc:URLSessionIntegration>
- <doc:UsingGeminiClient>
- ``GeminiProtocol``
- ``GeminiClient``
- ``GeminiURLResponse``
- ``GeminiResponseHeader``
- ``GeminiStatusCode``
- ``GeminiTLSMode``
- ``GeminiClientError``

### Gemtext

- <doc:ParsingGemtext>
- ``GemtextParser``
- ``GemtextParserOptions``
- ``GemtextDocument``
- ``GemtextLine``
- ``GemtextRenderer``
- ``GemtextPlainTextRenderOptions``
- ``GemtextMarkdownRenderOptions``

### Companion Specifications

- <doc:ParsingCompanionSpecifications>
- ``GeminiRobotsParser``
- ``GeminiRobotsPolicy``
- ``GeminiSubscriptionParser``
- ``GeminiSubscriptionFeed``

### Tutorial Guides

- <doc:TutorialBuildGeminiFetcher>
- <doc:TutorialParseAndRenderGemtext>
- <doc:TutorialCompanionSpecWorkflow>
