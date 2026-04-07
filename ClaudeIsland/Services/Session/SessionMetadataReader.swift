//
//  SessionMetadataReader.swift
//  ClaudeIsland
//
//  Reads Claude Code's per-session metadata files at ~/.claude/sessions/<pid>.json.
//  These files are Claude Code's own bookkeeping and contain an optional `name`
//  field — the same title shown by `/resume`. We surface that name as the
//  preferred session title instead of falling back to the first user message.
//
//  File format (observed 2026-04-06):
//    {
//      "pid": 45365,
//      "sessionId": "28267e63-f9d1-4b1e-8818-5591fd4cb247",
//      "cwd": "/Users/…",
//      "startedAt": 1775513659851,
//      "kind": "interactive",
//      "entrypoint": "cli",
//      "name": "reposition-overlay-top-right"   // optional, set after Claude picks a title
//    }
//

import Foundation

/// Minimal view over a session metadata JSON file.
struct SessionMetadata: Equatable {
    let pid: Int
    let sessionId: String
    let name: String?
}

enum SessionMetadataReader {
    /// Default directory where Claude Code writes session metadata.
    nonisolated static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
    }

    /// Find the `name` for a given sessionId by scanning a directory of
    /// `<pid>.json` files. Returns nil if the directory is missing, no file
    /// matches, or the matching file has no `name` set yet.
    nonisolated static func findName(for sessionId: String, in directory: URL = defaultDirectory) -> String? {
        findMetadata(for: sessionId, in: directory)?.name
    }

    /// Find the full metadata record for a given sessionId. Exposed separately
    /// so callers that want pid/cwd/etc. don't need a second pass.
    nonisolated static func findMetadata(for sessionId: String, in directory: URL = defaultDirectory) -> SessionMetadata? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let meta = decode(data) else { continue }
            if meta.sessionId == sessionId {
                return meta
            }
        }
        return nil
    }

    /// Decode a single metadata file's bytes. Returns nil on malformed JSON
    /// or missing required fields (`pid`, `sessionId`). `name` is optional.
    nonisolated static func decode(_ data: Data) -> SessionMetadata? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = json["pid"] as? Int,
              let sessionId = json["sessionId"] as? String else {
            return nil
        }
        let name = json["name"] as? String
        // Treat empty/whitespace-only names as "no name" so the caller's
        // fallback chain kicks in.
        let cleaned = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SessionMetadata(
            pid: pid,
            sessionId: sessionId,
            name: (cleaned?.isEmpty ?? true) ? nil : cleaned
        )
    }
}
