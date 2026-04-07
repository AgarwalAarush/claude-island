//
//  RemoteTranscriptMirror.swift
//  ClaudeIsland
//
//  Mirrors a remote (SSH) session's JSONL transcript to a host-namespaced
//  directory under `~/.claude/projects/` so the existing ConversationParser
//  pipeline can read it the same way it reads local transcripts.
//
//  The hook script (`Resources/claude-island-state.py`) tails the local JSONL
//  on the remote machine and forwards new bytes back over the existing socket
//  as a base64-encoded `jsonlChunk` field on the standard hook event. The Mac
//  side (SessionStore) calls `RemoteTranscriptMirror.write` to land each chunk
//  in the right place before scheduling its debounced parser sync.
//
//  Path policy: the destination is computed via `ConversationParser.sessionFilePath`
//  using `SessionState.transcriptCwd`, which prepends `/remote-<host>` to the
//  raw cwd for remote sessions. That guarantees mirrors from different machines
//  cannot collide in the projects directory.
//

import Foundation
import os

enum RemoteTranscriptMirrorError: Error {
    case invalidBase64
}

struct RemoteTranscriptMirror {
    private static let logger = Logger(subsystem: "com.claudeisland", category: "RemoteMirror")

    /// Decode a base64 chunk and write it to the local mirror file at the path
    /// `ConversationParser` will subsequently read from. `offset == 0` truncates
    /// the existing mirror (used on first sync and after `/clear` shrinks the
    /// source file); any non-zero offset appends to the existing file.
    ///
    /// - Parameters:
    ///   - sessionId: Claude Code session UUID — same value the parser uses.
    ///   - transcriptCwd: `SessionState.transcriptCwd` for this session, which
    ///     already encodes the host namespace for remote sessions. Local
    ///     sessions should never reach this method.
    ///   - chunkBase64: base64-encoded raw bytes from the remote JSONL.
    ///   - offset: byte offset in the *source* JSONL where the chunk begins.
    ///     Used as a "truncate vs append" signal here, not as a seek target.
    static func write(
        sessionId: String,
        transcriptCwd: String,
        chunkBase64: String,
        offset: Int
    ) throws {
        guard let bytes = Data(base64Encoded: chunkBase64) else {
            throw RemoteTranscriptMirrorError.invalidBase64
        }

        let filePath = ConversationParser.sessionFilePath(
            sessionId: sessionId,
            cwd: transcriptCwd
        )
        let dirPath = (filePath as NSString).deletingLastPathComponent

        let fm = FileManager.default
        if !fm.fileExists(atPath: dirPath) {
            try fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }

        let fileURL = URL(fileURLWithPath: filePath)

        if offset == 0 || !fm.fileExists(atPath: filePath) {
            // Truncate / create — the source was rewound (e.g. /clear) or this
            // is the first chunk we've ever received for this session.
            try bytes.write(to: fileURL, options: .atomic)
            logger.debug("Mirror init: \((filePath as NSString).lastPathComponent, privacy: .public) (\(bytes.count) bytes)")
            return
        }

        // Append. Open with FileHandle so we don't have to load the existing
        // file into memory just to add a few KB to the end.
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: bytes)
        logger.debug("Mirror append: \((filePath as NSString).lastPathComponent, privacy: .public) (+\(bytes.count) bytes @ offset \(offset))")
    }
}
