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
    ///
    /// The rect matches the actual rendered panel: NotchView constrains the opened
    /// panel to `notchSize.width × notchSize.height` and anchors it via
    /// `.padding(.top, menuBarHeight + topInset) .padding(.trailing, rightInset)`.
    /// An older revision of this method shrunk the rect by (-6, -30); that left a
    /// 6pt strip on the left and a 30pt strip on the bottom of the visible panel
    /// outside the hover rect, so hovering those bands fired the auto-close timer
    /// and collapsed the panel mid-interaction.
    func openedScreenRect(for size: CGSize) -> CGRect {
        CGRect(
            x: screenRect.maxX - size.width - Self.rightInset,
            y: screenRect.maxY - menuBarHeight - Self.topInset - size.height,
            width: size.width,
            height: size.height
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

    /// Check if a point is in the opened panel area, accounting for the current anchor.
    /// Includes a small grace inset so floating-point cursor jitter at the panel edge
    /// doesn't briefly flip hover state and trigger the mouse-leave close timer.
    func isPointInOpenedPanel(_ point: CGPoint, size: CGSize, anchor: PanelAnchor) -> Bool {
        panelScreenRect(for: size, anchor: anchor).insetBy(dx: -4, dy: -4).contains(point)
    }
}
