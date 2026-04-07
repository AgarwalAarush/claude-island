//
//  NotchTunables.swift
//  ClaudeIsland
//
//  Centralized timing/feel constants for the floating overlay.
//  Kept dependency-free so they can be unit-tested in isolation.
//

import Foundation

enum NotchTunables {
    /// Sustained-hover duration before the closed pill auto-expands.
    /// Short enough to feel responsive, long enough that mouse-overs in transit don't trigger.
    static let hoverOpenDelay: TimeInterval = 0.3

    /// Grace period between mouse leaving the opened panel and auto-collapse.
    /// Avoids immediate close on accidental cursor flicks across the edge.
    static let mouseLeaveCloseDelay: TimeInterval = 0.15
}
