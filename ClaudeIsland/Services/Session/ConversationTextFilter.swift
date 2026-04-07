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
    static func isSlashCommandOrMetaText(_ text: String) -> Bool {
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
    static func extractUserText(from message: [String: Any]) -> String? {
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
}
