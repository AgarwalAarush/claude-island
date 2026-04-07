//
//  ConversationTextFilter.swift
//  ClaudeIsland
//
//  Pure-logic helpers for filtering slash-command/meta text out of Claude
//  session transcripts. Lives outside ConversationParser so it can be
//  unit-tested in isolation (ConversationParser pulls in ChatMessage,
//  ToolResultData, os.log, and the rest of the parsing pipeline).
//

import Foundation

enum ConversationTextFilter {
    /// Returns true if the given text is a slash-command wrapper tag, a
    /// local-command-stdout echo, or the "Caveat:" meta prefix that Claude
    /// Code injects — i.e. content that should not be surfaced as a title
    /// or last-message preview.
    ///
    /// Slash commands like `/init` serialize as:
    ///     <command-message>init</command-message>\n<command-name>/init</command-name>
    /// The `<command-` prefix check catches every `<command-*>` variant
    /// (command-message, command-name, command-args, …) in one shot.
    nonisolated static func isSlashCommandOrMetaText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<command-")
            || trimmed.hasPrefix("<local-command")
            || trimmed.hasPrefix("Caveat:")
    }

    /// Extracts the first user-facing text out of a user-message JSON
    /// payload, handling both the plain-string content form and the
    /// content-block array form (which is how Claude Code emits expanded
    /// slash-command prompts). Returns nil if every candidate is filtered
    /// out by `isSlashCommandOrMetaText`.
    nonisolated static func extractUserText(from message: [String: Any]) -> String? {
        if let str = message["content"] as? String {
            return isSlashCommandOrMetaText(str) ? nil : str
        }
        if let blocks = message["content"] as? [[String: Any]] {
            for block in blocks {
                guard block["type"] as? String == "text",
                      let text = block["text"] as? String else { continue }
                if !isSlashCommandOrMetaText(text) {
                    return text
                }
            }
        }
        return nil
    }

    /// Returns true if the given JSONL line represents a genuine `/clear`
    /// user command — as opposed to a tool result whose body happens to
    /// contain the literal string `<command-name>/clear</command-name>`
    /// (e.g. from editing ConversationParser.swift itself, which was a
    /// real self-referential bug in this project).
    ///
    /// A real user slash-command has `type == "user"` and
    /// `message.content` as a plain **string** containing the command
    /// tags. Tool results have `message.content` as an **array** of
    /// content blocks, so excluding the array form drops the whole class
    /// of false positives in one check.
    nonisolated static func isClearCommandLine(_ line: String) -> Bool {
        // Fast reject: if the literal pattern isn't on this line, it's not a /clear.
        guard line.contains("<command-name>/clear</command-name>") else {
            return false
        }

        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "user",
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return false
        }

        return content.contains("<command-name>/clear</command-name>")
    }
}
