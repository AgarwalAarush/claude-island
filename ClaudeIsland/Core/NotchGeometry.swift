//
//  NotchGeometry.swift
//  ClaudeIsland
//
//  Geometry calculations for the floating top-right overlay
//

import CoreGraphics
import Foundation

/// Where the opened panel anchors itself on the screen.
/// Most modes (chat, stats, menu, instances) anchor to the top-right corner.
/// The plan viewer uses `.center` so a full-width markdown plan has room to breathe.
enum PanelAnchor: Sendable {
    case topTrailing
    case center
}

/// Pure geometry calculations for the floating overlay
struct NotchGeometry: Sendable {
    let deviceNotchRect: CGRect
    let screenRect: CGRect
    let windowHeight: CGFloat
    let menuBarHeight: CGFloat

    /// Padding between the overlay and the screen edges
    static let topInset: CGFloat = 8
    static let rightInset: CGFloat = 8

    /// The closed-state indicator rect in screen coordinates (for hit testing with global mouse position)
    var notchScreenRect: CGRect {
        CGRect(
            x: screenRect.maxX - deviceNotchRect.width - Self.rightInset,
            y: screenRect.maxY - menuBarHeight - Self.topInset - deviceNotchRect.height,
            width: deviceNotchRect.width,
            height: deviceNotchRect.height
        )
    }

    /// The opened panel rect in screen coordinates for a given size, anchored top-right.
    /// Used by most modes; `panelScreenRect(for:anchor:)` is the preferred entry point.
    func openedScreenRect(for size: CGSize) -> CGRect {
        // Match the actual rendered panel size (tuned to match visual output)
        let width = size.width - 6
        let height = size.height - 30
        return CGRect(
            x: screenRect.maxX - width - Self.rightInset,
            y: screenRect.maxY - menuBarHeight - Self.topInset - height,
            width: width,
            height: height
        )
    }

    /// The opened panel rect in screen coordinates for a given size + anchor.
    /// Single entry point used by both the SwiftUI layout and the hit-test pipeline
    /// so the corner/center math can never drift between them.
    func panelScreenRect(for size: CGSize, anchor: PanelAnchor) -> CGRect {
        switch anchor {
        case .topTrailing:
            return openedScreenRect(for: size)
        case .center:
            let width = size.width
            let height = size.height
            return CGRect(
                x: screenRect.midX - width / 2,
                y: screenRect.midY - height / 2,
                width: width,
                height: height
            )
        }
    }

    /// Check if a point is in the closed-state indicator area (with padding for easier interaction)
    func isPointInNotch(_ point: CGPoint) -> Bool {
        notchScreenRect.insetBy(dx: -10, dy: -5).contains(point)
    }

    /// Check if a point is in the opened panel area (top-right anchored — legacy helper)
    func isPointInOpenedPanel(_ point: CGPoint, size: CGSize) -> Bool {
        openedScreenRect(for: size).contains(point)
    }

    /// Check if a point is outside the opened panel (top-right anchored — legacy helper)
    func isPointOutsidePanel(_ point: CGPoint, size: CGSize) -> Bool {
        !openedScreenRect(for: size).contains(point)
    }
}
