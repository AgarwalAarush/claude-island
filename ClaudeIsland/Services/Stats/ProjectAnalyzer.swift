//
//  ProjectAnalyzer.swift
//  ClaudeIsland
//
//  Scans a project directory for LOC/language stats and reads .git/config for repo identity.
//  Results are cached per cwd for 5 minutes to avoid redundant I/O.
//

import Foundation

struct ProjectScanResult: Equatable, Sendable {
    let cwd: String
    let languageLines: [String: Int]  // e.g. "Swift" → 4200
    let totalLines: Int
    let fileCount: Int
    let repoSlug: String?             // "owner/repo" or nil
    let remoteURL: String?
    let scannedAt: Date
}

actor ProjectAnalyzer {
    static let shared = ProjectAnalyzer()

    private var cache: [String: ProjectScanResult] = [:]
    private let cacheTTL: TimeInterval = 300  // 5 minutes

    // MARK: - Public API

    func scan(cwd: String) async -> ProjectScanResult? {
        // Return cached result if still fresh
        if let cached = cache[cwd], Date().timeIntervalSince(cached.scannedAt) < cacheTTL {
            return cached
        }

        // Run file I/O off the main actor on a utility task
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<ProjectScanResult?, Never>) in
            Task.detached(priority: .utility) {
                let r = Self.performScan(cwd: cwd)
                continuation.resume(returning: r)
            }
        }

        if let result {
            cache[cwd] = result
        }
        return result
    }

    func cachedResult(for cwd: String) -> ProjectScanResult? {
        cache[cwd]
    }

    // MARK: - Scanner

    private static let skippedDirs: Set<String> = [
        "node_modules", ".git", "build", "dist", "__pycache__",
        ".build", "DerivedData", "vendor", "Pods", ".swiftpm",
        ".next", "out", "coverage", ".turbo"
    ]

    private static let extensionToLanguage: [String: String] = [
        "swift": "Swift",
        "py": "Python",
        "ts": "TypeScript",
        "tsx": "TypeScript",
        "js": "JavaScript",
        "jsx": "JavaScript",
        "go": "Go",
        "rs": "Rust",
        "kt": "Kotlin",
        "kts": "Kotlin",
        "java": "Java",
        "rb": "Ruby",
        "cs": "C#",
        "cpp": "C++",
        "cc": "C++",
        "cxx": "C++",
        "c": "C",
        "h": "C",
        "hpp": "C++",
        "m": "Objective-C",
        "mm": "Objective-C",
        "sh": "Shell",
        "bash": "Shell",
        "zsh": "Shell",
    ]

    private static func performScan(cwd: String) -> ProjectScanResult? {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: cwd, isDirectory: true)

        guard fm.fileExists(atPath: cwd) else { return nil }

        var languageLines: [String: Int] = [:]
        var totalLines = 0
        var fileCount = 0
        let fileCap = 10_000

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            // Skip blacklisted directories
            if let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir {
                if skippedDirs.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard let isFile = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                  isFile else { continue }

            fileCount += 1
            if fileCount > fileCap { break }

            let ext = url.pathExtension.lowercased()
            guard let language = extensionToLanguage[ext] else { continue }

            let loc = countNonBlankLines(at: url)
            if loc > 0 {
                languageLines[language, default: 0] += loc
                totalLines += loc
            }
        }

        // Parse .git/config for repo slug
        let (repoSlug, remoteURL) = parseGitConfig(cwd: cwd)

        return ProjectScanResult(
            cwd: cwd,
            languageLines: languageLines,
            totalLines: totalLines,
            fileCount: fileCount,
            repoSlug: repoSlug,
            remoteURL: remoteURL,
            scannedAt: Date()
        )
    }

    private static func countNonBlankLines(at url: URL) -> Int {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    private static func parseGitConfig(cwd: String) -> (slug: String?, remoteURL: String?) {
        let configPath = cwd + "/.git/config"
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return (nil, nil)
        }

        var inOriginSection = false
        var foundURL: String?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inOriginSection = trimmed == "[remote \"origin\"]"
                continue
            }
            if inOriginSection, trimmed.hasPrefix("url") {
                // url = https://github.com/owner/repo.git  OR  git@github.com:owner/repo.git
                let parts = trimmed.components(separatedBy: "=")
                guard parts.count >= 2 else { continue }
                let raw = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
                foundURL = raw
                break
            }
        }

        guard let raw = foundURL else { return (nil, nil) }

        let slug = extractSlug(from: raw)
        return (slug, raw)
    }

    /// Extract "owner/repo" from HTTPS or SSH remote URL
    private static func extractSlug(from url: String) -> String? {
        var s = url
        // Strip .git suffix
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }

        // HTTPS: https://github.com/owner/repo
        if let range = s.range(of: "github.com/") {
            let after = String(s[range.upperBound...])
            let parts = after.components(separatedBy: "/").filter { !$0.isEmpty }
            if parts.count >= 2 { return "\(parts[0])/\(parts[1])" }
        }

        // SSH: git@github.com:owner/repo
        if let colonIdx = s.firstIndex(of: ":") {
            let after = String(s[s.index(after: colonIdx)...])
            let parts = after.components(separatedBy: "/").filter { !$0.isEmpty }
            if parts.count >= 2 { return "\(parts[0])/\(parts[1])" }
        }

        return nil
    }
}
