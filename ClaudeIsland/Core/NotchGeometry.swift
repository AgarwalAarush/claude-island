//
//  NotchGeometry.swift
//  ClaudeIsland
//
//  Geometry calculations for the floating top-right overlay
//

import CoreGraphics
import Foundation

/// Pure geometry calculations for the top-right floating overlay
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

    /// The opened panel rect in screen coordinates for a given size
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

    /// Check if a point is in the closed-state indicator area (with padding for easier interaction)
    func isPointInNotch(_ point: CGPoint) -> Bool {
        notchScreenRect.insetBy(dx: -10, dy: -5).contains(point)
    }

    /// Check if a point is in the opened panel area
    func isPointInOpenedPanel(_ point: CGPoint, size: CGSize) -> Bool {
        openedScreenRect(for: size).contains(point)
    }

    /// Check if a point is outside the opened panel (for closing)
    func isPointOutsidePanel(_ point: CGPoint, size: CGSize) -> Bool {
        !openedScreenRect(for: size).contains(point)
    }
}
