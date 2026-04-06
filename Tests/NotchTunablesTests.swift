//
//  NotchTunablesTests.swift
//
//  Tests for the timing/feel constants in NotchTunables.
//  These are tiny by design — pinning the values prevents accidental
//  regressions to "feels broken" delays.
//

import Foundation

@main
struct NotchTunablesTests {
    static func main() {
        test("hoverOpenDelay is 0.3s — short enough to feel responsive") {
            assertEqual(NotchTunables.hoverOpenDelay, 0.3, "hoverOpenDelay")
        }

        test("hoverOpenDelay is in a sane range (.1 ≤ delay ≤ 1.0)") {
            assertTrue(NotchTunables.hoverOpenDelay >= 0.1, "delay not too short")
            assertTrue(NotchTunables.hoverOpenDelay <= 1.0, "delay not too long")
        }

        test("mouseLeaveCloseDelay exists and is in a sane range") {
            assertTrue(NotchTunables.mouseLeaveCloseDelay >= 0.1, "close delay not too short")
            assertTrue(NotchTunables.mouseLeaveCloseDelay <= 1.0, "close delay not too long")
        }

        finish("NotchTunablesTests")
    }
}
