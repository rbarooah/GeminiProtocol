import Foundation
import GeminiProtocol

@main
struct AntennaMirrorExample {
    private static let frontPageURL = URL(string: "gemini://warmedal.se/~antenna/")!
    private static let defaultOutputDirectoryName = "AntennaMirrorOutput"

    static func main() async {
        do {
            let outputDirectory = try outputDirectoryFromArguments(CommandLine.arguments)
            try prepareOutputDirectories(outputDirectory)

            print("Fetching front page: \(frontPageURL.absoluteString)")
            let frontPage = try await fetchPage(frontPageURL)
            let frontPagePath = outputDirectory.appendingPathComponent("front-page.md")
            try frontPage.markdown.write(to: frontPagePath, atomically: true, encoding: .utf8)

            let references = extractFrontPageReferences(
                from: frontPage.document,
                baseURL: frontPageURL
            )
            print("Found \(references.count) unique Gemini links on the front page.")

            let articlesDirectory = outputDirectory.appendingPathComponent("articles", isDirectory: true)
            var usedFileNames: Set<String> = []
            var mirrored: [MirroredArticle] = []
            var failures: [MirrorFailure] = []

            for (index, reference) in references.enumerated() {
                let progress = "[\(index + 1)/\(references.count)]"
                print("\(progress) Fetching \(reference.url.absoluteString)")

                do {
                    let article = try await mirrorArticle(
                        reference: reference,
                        ordinal: index + 1,
                        outputDirectory: articlesDirectory,
                        usedFileNames: &usedFileNames
                    )
                    mirrored.append(article)
                } catch {
                    print("\(progress) Failed: \(error.localizedDescription)")
                    failures.append(MirrorFailure(url: reference.url, reason: error.localizedDescription))
                }
            }

            try writeIndexFile(
                outputDirectory: outputDirectory,
                frontPageURL: frontPageURL,
                frontPageTitle: frontPage.title,
                mirrored: mirrored,
                failures: failures
            )

            print("Done.")
            print("Output folder: \(outputDirectory.path)")
            print("Front page markdown: \(frontPagePath.path)")
            print("Mirrored articles: \(mirrored.count)")
            if !failures.isEmpty {
                print("Failed fetches: \(failures.count)")
            }
        } catch {
            fputs("AntennaMirrorExample failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func outputDirectoryFromArguments(_ arguments: [String]) throws -> URL {
        guard arguments.count <= 2 else {
            throw MirrorError.invalidArguments(
                "Usage: swift run AntennaMirrorExample [output-directory]"
            )
        }

        if arguments.count == 2 {
            return URL(fileURLWithPath: arguments[1], isDirectory: true)
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(defaultOutputDirectoryName, isDirectory: true)
    }

    private static func prepareOutputDirectories(_ outputDirectory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let articlesDirectory = outputDirectory.appendingPathComponent("articles", isDirectory: true)
        if fileManager.fileExists(atPath: articlesDirectory.path) {
            try fileManager.removeItem(at: articlesDirectory)
        }

        try fileManager.createDirectory(at: articlesDirectory, withIntermediateDirectories: true)
    }

    private static func fetchPage(_ url: URL) async throws -> ParsedPage {
        let (header, body, _) = try await fetchSuccessBody(from: url)
        let markdown: String
        let title: String
        let document: GemtextDocument

        if header.meta.lowercased().hasPrefix("text/gemini") {
            guard let source = String(data: body, encoding: .utf8) else {
                throw MirrorError.invalidUTF8(url)
            }

            document = try GemtextParser.parse(
                source,
                options: .init(mode: .permissive, baseURL: url)
            )
            markdown = GemtextRenderer.markdown(
                from: document,
                options: .init(
                    normalizeWhitespace: true,
                    includePreformatAltTextAsInfoString: true
                )
            )
            title = firstHeadingTitle(in: document) ?? url.absoluteString
        } else if header.meta.lowercased().hasPrefix("text/") {
            guard let source = String(data: body, encoding: .utf8) else {
                throw MirrorError.invalidUTF8(url)
            }

            document = GemtextDocument(source: source, lines: [], diagnostics: [])
            markdown = "```text\n\(source)\n```"
            title = url.absoluteString
        } else {
            document = GemtextDocument(source: "", lines: [], diagnostics: [])
            markdown = """
            # Non-text response

            Source: <\(url.absoluteString)>

            Meta: `\(header.meta)`

            Body size: \(body.count) bytes
            """
            title = url.absoluteString
        }

        return ParsedPage(
            url: url,
            header: header,
            document: document,
            markdown: markdown,
            title: title
        )
    }

    private static func fetchSuccessBody(
        from url: URL,
        timeout: TimeInterval = 45
    ) async throws -> (GeminiResponseHeader, Data, GeminiTLSMode) {
        let request = URLRequest(url: url)
        let tlsModes: [GeminiTLSMode] = [.systemTrust, .insecureNoVerification]
        var lastError: Error?

        for mode in tlsModes {
            do {
                let client = try GeminiClient(request: request, tlsMode: mode)
                let (header, maybeBody) = try await client.start(timeout: timeout)

                guard header.status.isSuccess else {
                    throw MirrorError.nonSuccessStatus(url: url, status: header.status, meta: header.meta)
                }

                guard let body = maybeBody else {
                    throw MirrorError.missingBody(url)
                }

                return (header, body, mode)
            } catch {
                lastError = error
                continue
            }
        }

        throw MirrorError.fetchFailed(url, lastError)
    }

    private static func extractFrontPageReferences(
        from document: GemtextDocument,
        baseURL: URL
    ) -> [FrontPageReference] {
        var references: [FrontPageReference] = []
        var seen: Set<String> = []

        for line in document.lines {
            guard case .link(let linkLine) = line else { continue }
            guard let resolved = resolveURL(from: linkLine, baseURL: baseURL) else { continue }
            guard resolved.scheme?.lowercased() == "gemini" else { continue }
            guard resolved != baseURL else { continue }

            let key = resolved.absoluteString
            guard seen.insert(key).inserted else { continue }

            let label = sanitizedLabel(linkLine.label) ?? resolved.absoluteString
            references.append(FrontPageReference(url: resolved, label: label))
        }

        return references
    }

    private static func resolveURL(from link: GemtextLinkLine, baseURL: URL) -> URL? {
        if let resolved = link.resolvedURL {
            return resolved
        }
        if let absolute = URL(string: link.target), absolute.scheme != nil {
            return absolute
        }
        return URL(string: link.target, relativeTo: baseURL)?.absoluteURL
    }

    private static func sanitizedLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func mirrorArticle(
        reference: FrontPageReference,
        ordinal: Int,
        outputDirectory: URL,
        usedFileNames: inout Set<String>
    ) async throws -> MirroredArticle {
        let page = try await fetchPage(reference.url)
        let fileName = uniqueFileName(for: reference.url, ordinal: ordinal, used: &usedFileNames)
        let outputPath = outputDirectory.appendingPathComponent(fileName, isDirectory: false)
        try page.markdown.write(to: outputPath, atomically: true, encoding: .utf8)

        return MirroredArticle(
            sourceURL: reference.url,
            sourceLabel: reference.label,
            title: page.title,
            relativePath: "articles/\(fileName)",
            meta: page.header.meta
        )
    }

    private static func uniqueFileName(
        for url: URL,
        ordinal: Int,
        used: inout Set<String>
    ) -> String {
        let base = slug(from: url)
        let prefix = String(format: "%03d", ordinal)
        var candidate = "\(prefix)-\(base).md"
        var collision = 2

        while used.contains(candidate) {
            candidate = "\(prefix)-\(base)-\(collision).md"
            collision += 1
        }

        used.insert(candidate)
        return candidate
    }

    private static func slug(from url: URL) -> String {
        let raw = url.path.isEmpty ? (url.host ?? "article") : url.path
        let scalars = raw.unicodeScalars.map { scalar -> Character in
            let allowed = CharacterSet.alphanumerics.contains(scalar)
            return allowed ? Character(scalar) : "-"
        }
        var cleaned = String(scalars)
        while cleaned.contains("--") {
            cleaned = cleaned.replacingOccurrences(of: "--", with: "-")
        }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if cleaned.isEmpty {
            cleaned = "article"
        }
        return cleaned.lowercased()
    }

    private static func firstHeadingTitle(in document: GemtextDocument) -> String? {
        for line in document.lines {
            guard case .heading(let heading) = line, heading.level == 1 else { continue }
            let title = heading.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return title
            }
        }
        return nil
    }

    private static func writeIndexFile(
        outputDirectory: URL,
        frontPageURL: URL,
        frontPageTitle: String,
        mirrored: [MirroredArticle],
        failures: [MirrorFailure]
    ) throws {
        var lines: [String] = []
        lines.append("# Antenna Mirror")
        lines.append("")
        lines.append("Source front page: <\(frontPageURL.absoluteString)>")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        lines.append("## Front Page")
        lines.append("- [\(escapeMarkdown(frontPageTitle))](front-page.md)")
        lines.append("")
        lines.append("## Mirrored Articles")
        lines.append("")

        if mirrored.isEmpty {
            lines.append("_No articles mirrored._")
        } else {
            for article in mirrored {
                let display = escapeMarkdown(article.sourceLabel)
                lines.append("- [\(display)](\(article.relativePath))")
                lines.append("  - Source: <\(article.sourceURL.absoluteString)>")
                lines.append("  - Meta: `\(article.meta)`")
            }
        }

        if !failures.isEmpty {
            lines.append("")
            lines.append("## Failed Fetches")
            lines.append("")
            for failure in failures {
                lines.append("- <\(failure.url.absoluteString)>")
                lines.append("  - \(escapeMarkdown(failure.reason))")
            }
        }

        lines.append("")
        let index = lines.joined(separator: "\n")
        let indexPath = outputDirectory.appendingPathComponent("index.md", isDirectory: false)
        try index.write(to: indexPath, atomically: true, encoding: .utf8)
    }

    private static func escapeMarkdown(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}

private struct ParsedPage {
    let url: URL
    let header: GeminiResponseHeader
    let document: GemtextDocument
    let markdown: String
    let title: String
}

private struct FrontPageReference {
    let url: URL
    let label: String
}

private struct MirroredArticle {
    let sourceURL: URL
    let sourceLabel: String
    let title: String
    let relativePath: String
    let meta: String
}

private struct MirrorFailure {
    let url: URL
    let reason: String
}

private enum MirrorError: LocalizedError {
    case invalidArguments(String)
    case fetchFailed(URL, Error?)
    case nonSuccessStatus(url: URL, status: GeminiStatusCode, meta: String)
    case missingBody(URL)
    case invalidUTF8(URL)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .fetchFailed(let url, let lastError):
            if let lastError {
                return "Failed to fetch \(url.absoluteString): \(lastError.localizedDescription)"
            }
            return "Failed to fetch \(url.absoluteString)"
        case .nonSuccessStatus(let url, let status, let meta):
            return "Non-success response from \(url.absoluteString): \(status.rawValue) \(meta)"
        case .missingBody(let url):
            return "Missing response body for \(url.absoluteString)"
        case .invalidUTF8(let url):
            return "Response body is not valid UTF-8 for \(url.absoluteString)"
        }
    }
}
