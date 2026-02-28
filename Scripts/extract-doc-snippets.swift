#!/usr/bin/env swift

import Foundation

// MARK: - Configuration

struct Config {
    static let testsPath = "Tests/StatoscopeTests/Examples"
    static let docsBasePath = "Sources/Statoscope/Documentation.docc/Tutorials/StatoscopeTutorial/01-Basics"

    // Map tutorial files to their doc directories
    static let tutorialToDocDir: [String: String] = [
        "Tutorial01_StateAndWhen.swift": "01-StateAndWhen",
        "Tutorial02_StateWhenAndEffects.swift": "02-StateWhenAndEffects",
        "Tutorial03_Middleware.swift": "03-Middleware",
        "Tutorial04_Injection.swift": "04-Injection",
        "Tutorial05_Scopes.swift": "05-Scopes",
        "Tutorial06_Testing.swift": "06-Testing"
    ]
}

// MARK: - Models

struct ExtractedSnippet {
    let filename: String
    let content: String
    let sourceFile: String
    let startLine: Int
    let endLine: Int
}

// MARK: - Extraction Engine

class SnippetExtractor {

    struct SnippetState {
        var startLine: Int
        var lines: [String]
        var isActive: Bool  // Currently collecting lines
    }

    func extractSnippets(from filePath: String) throws -> [ExtractedSnippet] {
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        // Track all snippets (supports multiple begin/end pairs for same file)
        var snippets: [String: SnippetState] = [:]

        for (index, line) in lines.enumerated() {
            // Extract all @extract markers from this line
            let beginMarkers = extractMarkers(from: line, marker: "@extract:begin")
            let endMarkers = extractMarkers(from: line, marker: "@extract:end")

            // Process end markers first (pause collection)
            for filename in endMarkers {
                if snippets[filename] != nil {
                    snippets[filename]?.isActive = false
                }
            }

            // Process begin markers (start/resume collection)
            for filename in beginMarkers {
                if snippets[filename] == nil {
                    // First time seeing this snippet - create it
                    snippets[filename] = SnippetState(
                        startLine: index + 1,
                        lines: [],
                        isActive: true
                    )
                } else {
                    // Resume collection for existing snippet
                    snippets[filename]?.isActive = true
                }
            }

            // Add current line to all active snippets (if it's not just a marker line)
            let isMarkerOnlyLine = line.trimmingCharacters(in: .whitespaces).hasPrefix("//") &&
                                   (line.contains("@extract:begin") || line.contains("@extract:end"))

            if !isMarkerOnlyLine {
                for (filename, var snippet) in snippets where snippet.isActive {
                    snippet.lines.append(line)
                    snippets[filename] = snippet
                }
            }
        }

        // Convert all snippets to ExtractedSnippet
        var completedSnippets: [ExtractedSnippet] = []
        for (filename, snippet) in snippets {
            let content = processContent(snippet.lines)
            completedSnippets.append(ExtractedSnippet(
                filename: filename + ".swift",
                content: content,
                sourceFile: filePath,
                startLine: snippet.startLine,
                endLine: lines.count
            ))
        }

        return completedSnippets.sorted { $0.filename < $1.filename }
    }

    private func extractMarkers(from line: String, marker: String) -> [String] {
        // Find all instances of the marker in this line
        var filenames: [String] = []
        var searchRange = line.startIndex..<line.endIndex

        while let range = line.range(of: marker, range: searchRange) {
            // Extract the filename after the marker
            let afterMarker = line[range.upperBound...]
            let filename = afterMarker.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespacesAndNewlines).first ?? ""

            if !filename.isEmpty {
                filenames.append(filename)
            }

            // Continue searching after this match
            searchRange = range.upperBound..<line.endIndex
        }

        return filenames
    }

    private func processContent(_ lines: [String]) -> String {
        var processed = lines

        // Remove leading/trailing empty lines
        while processed.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            processed.removeFirst()
        }
        while processed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            processed.removeLast()
        }

        // Find minimum indentation (excluding empty lines)
        let nonEmptyLines = processed.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonEmptyLines.isEmpty else { return "" }

        let minIndent = nonEmptyLines.map { line -> Int in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return Int.max }
            return line.count - line.trimmingCharacters(in: .whitespaces).count
        }.min() ?? 0

        // Remove the minimum indentation from all lines
        let dedented = processed.map { line -> String in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
            let indent = line.prefix(while: { $0.isWhitespace }).count
            let removeCount = min(indent, minIndent)
            return String(line.dropFirst(removeCount))
        }

        return dedented.joined(separator: "\n") + "\n"
    }
}

// MARK: - File Writer

class SnippetWriter {

    func writeSnippet(_ snippet: ExtractedSnippet, to outputPath: String) throws {
        let fileURL = URL(fileURLWithPath: outputPath)
        let directoryURL = fileURL.deletingLastPathComponent()

        // Create directory if needed
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Write content
        try snippet.content.write(to: fileURL, atomically: true, encoding: .utf8)

        print("✅ Generated: \(outputPath)")
        print("   Source: \(snippet.sourceFile):\(snippet.startLine)-\(snippet.endLine)")
    }
}

// MARK: - Main Script

func main() {
    let fileManager = FileManager.default
    let currentDirectory = fileManager.currentDirectoryPath

    print("📂 Working directory: \(currentDirectory)")
    print("🔍 Extracting documentation snippets...\n")

    let extractor = SnippetExtractor()
    let writer = SnippetWriter()

    var totalSnippets = 0
    var totalFiles = 0

    // Process each tutorial file
    for (tutorialFile, docDir) in Config.tutorialToDocDir.sorted(by: { $0.key < $1.key }) {
        let testFilePath = "\(currentDirectory)/\(Config.testsPath)/\(tutorialFile)"

        guard fileManager.fileExists(atPath: testFilePath) else {
            print("⚠️  Test file not found: \(testFilePath)")
            continue
        }

        print("📖 Processing: \(tutorialFile)")

        do {
            let snippets = try extractor.extractSnippets(from: testFilePath)

            if snippets.isEmpty {
                print("   No snippets found\n")
                continue
            }

            totalFiles += 1

            for snippet in snippets {
                let outputPath = "\(currentDirectory)/\(Config.docsBasePath)/\(docDir)/\(snippet.filename)"
                try writer.writeSnippet(snippet, to: outputPath)
                totalSnippets += 1
            }

            print("")

        } catch {
            print("❌ Error processing \(tutorialFile): \(error)\n")
        }
    }

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("✨ Extraction complete!")
    print("   Files processed: \(totalFiles)")
    print("   Snippets generated: \(totalSnippets)")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
}

// Run the script
main()
