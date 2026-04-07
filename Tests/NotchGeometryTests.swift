//
//  NotchGeometryTests.swift
//
//  Tests for the pure geometry math used to position the floating overlay.
//  Compiled together with ClaudeIsland/Core/NotchGeometry.swift via scripts/test.sh.
//

import CoreGraphics
import Foundation

@main
struct NotchGeometryTests {
    // Reference values reused across cases — a typical 1440×900 display with a
    // 24pt menu bar (non-notched) and the standard 224×38 indicator size.
    static let screenRect = CGRect(x: 0, y: 0, width: 1440, height: 900)
    static let menuBarHeight: CGFloat = 24
    static let indicatorSize = CGSize(width: 224, height: 38)
    static let geometry = NotchGeometry(
        deviceNotchRect: CGRect(origin: .zero, size: indicatorSize),
        screenRect: screenRect,
        windowHeight: 750,
        menuBarHeight: menuBarHeight
    )

    static func main() {
        test("notchScreenRect is anchored to top-right with rightInset") {
            let r = geometry.notchScreenRect
            assertEqual(r.maxX, screenRect.maxX - NotchGeometry.rightInset, "right edge has rightInset gap")
            assertEqual(r.width, indicatorSize.width, "width unchanged from deviceNotchRect")
            assertEqual(r.height, indicatorSize.height, "height unchanged from deviceNotchRect")
        }

        test("notchScreenRect sits below the menu bar with topInset") {
            let r = geometry.notchScreenRect
            // In AppKit screen coords (origin bottom-left), the top edge is r.maxY
            // and "below the menu bar" means it's `menuBarHeight + topInset` down from screen top.
            assertEqual(
                r.maxY,
                screenRect.maxY - menuBarHeight - NotchGeometry.topInset,
                "top edge sits menuBar+topInset below screen top"
            )
        }

        test("openedScreenRect is also top-right anchored") {
            let r = geometry.openedScreenRect(for: CGSize(width: 480, height: 320))
            assertEqual(r.maxX, screenRect.maxX - NotchGeometry.rightInset, "opened panel right edge has inset")
            assertEqual(
                r.maxY,
                screenRect.maxY - menuBarHeight - NotchGeometry.topInset,
                "opened panel top edge below menu bar"
            )
        }

        test("openedScreenRect grows leftward and downward as size increases") {
            let small = geometry.openedScreenRect(for: CGSize(width: 480, height: 320))
            let large = geometry.openedScreenRect(for: CGSize(width: 600, height: 580))
            // Right and top edges stay locked
            assertEqual(small.maxX, large.maxX, "right edge locked across sizes")
            assertEqual(small.maxY, large.maxY, "top edge locked across sizes")
            // Larger panel extends further left and further down
            assertTrue(large.minX < small.minX, "larger width extends further left")
            assertTrue(large.minY < small.minY, "larger height extends further down")
        }

        test("isPointInNotch hit area extends beyond the indicator for hover comfort") {
            let r = geometry.notchScreenRect
            // A point 9pt left of the indicator's left edge should still hit (10pt buffer)
            let leftBuffer = CGPoint(x: r.minX - 9, y: r.midY)
            assertTrue(geometry.isPointInNotch(leftBuffer), "9pt left of indicator is inside hover area")
            // A point 11pt left should NOT hit
            let outsideLeft = CGPoint(x: r.minX - 11, y: r.midY)
            assertTrue(!geometry.isPointInNotch(outsideLeft), "11pt left of indicator is outside hover area")
        }

        test("isPointInOpenedPanel matches openedScreenRect bounds") {
            let size = CGSize(width: 480, height: 320)
            let panelRect = geometry.openedScreenRect(for: size)
            let inside = CGPoint(x: panelRect.midX, y: panelRect.midY)
            let outside = CGPoint(x: panelRect.minX - 1, y: panelRect.midY)
            assertTrue(geometry.isPointInOpenedPanel(inside, size: size), "midpoint is inside")
            assertTrue(!geometry.isPointInOpenedPanel(outside, size: size), "1pt left of panel is outside")
        }

        test("topInset and rightInset constants are 8pt") {
            assertEqual(NotchGeometry.topInset, 8, "topInset is 8pt")
            assertEqual(NotchGeometry.rightInset, 8, "rightInset is 8pt")
        }

        test("panelScreenRect(.topTrailing) matches legacy openedScreenRect") {
            let size = CGSize(width: 600, height: 580)
            let legacy = geometry.openedScreenRect(for: size)
            let routed = geometry.panelScreenRect(for: size, anchor: .topTrailing)
            assertEqual(routed.minX, legacy.minX, "minX matches legacy path")
            assertEqual(routed.minY, legacy.minY, "minY matches legacy path")
            assertEqual(routed.width, legacy.width, "width matches legacy path")
            assertEqual(routed.height, legacy.height, "height matches legacy path")
        }

        test("panelScreenRect(.center) sits at screen midpoint") {
            let size = CGSize(width: 720, height: 600)
            let r = geometry.panelScreenRect(for: size, anchor: .center)
            assertEqual(r.midX, screenRect.midX, "panel is horizontally centered on screen")
            assertEqual(r.midY, screenRect.midY, "panel is vertically centered on screen")
            assertEqual(r.width, size.width, "width is unshrunk (no tuning offset for center anchor)")
            assertEqual(r.height, size.height, "height is unshrunk (no tuning offset for center anchor)")
        }

        test("panelScreenRect(.center) stays centered as size changes") {
            let small = geometry.panelScreenRect(for: CGSize(width: 480, height: 320), anchor: .center)
            let large = geometry.panelScreenRect(for: CGSize(width: 720, height: 600), anchor: .center)
            assertEqual(small.midX, large.midX, "midX stays locked to screen midX")
            assertEqual(small.midY, large.midY, "midY stays locked to screen midY")
            // Larger panel extends further in all directions from the center
            assertTrue(large.minX < small.minX, "larger panel extends further left")
            assertTrue(large.maxX > small.maxX, "larger panel extends further right")
            assertTrue(large.minY < small.minY, "larger panel extends further down")
            assertTrue(large.maxY > small.maxY, "larger panel extends further up")
        }

        finish("NotchGeometryTests")
    }
}
