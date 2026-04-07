//
//  NotchViewController.swift
//  ClaudeIsland
//
//  Hosts the SwiftUI NotchView in AppKit with click-through support
//

import AppKit
import SwiftUI

/// Custom NSHostingView that only accepts mouse events within the panel bounds.
/// Clicks outside the panel pass through to windows behind.
class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var hitTestRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only accept hits within the panel rect
        guard hitTestRect().contains(point) else {
            return nil  // Pass through to windows behind
        }
        return super.hitTest(point)
    }
}

class NotchViewController: NSViewController {
    private let viewModel: NotchViewModel
    private var hostingView: PassThroughHostingView<NotchView>!

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        hostingView = PassThroughHostingView(rootView: NotchView(viewModel: viewModel))

        // Calculate the hit-test rect based on panel state.
        //
        // Window coordinates: origin at bottom-left, Y increases upward.
        // Screen coordinates: origin at bottom-left, Y increases upward.
        // The window is positioned so its top edge aligns with the top of the screen:
        //     window.minY (screen) = screenRect.maxY - windowHeight
        // So to convert a screen-space rect to window-local coords we subtract
        // that window origin from the rect.
        hostingView.hitTestRect = { [weak self] in
            guard let self = self else { return .zero }
            let vm = self.viewModel
            let geometry = vm.geometry
            let windowOriginY = geometry.screenRect.maxY - geometry.windowHeight
            let windowOriginX = geometry.screenRect.minX

            switch vm.status {
            case .opened:
                // Route through the single source of truth on the view model — works for
                // both top-right anchored panels (chat/stats/menu/instances) and
                // center-anchored panels (plan viewer) with no per-mode branching.
                let screenRect = vm.currentPanelScreenRect
                return CGRect(
                    x: screenRect.minX - windowOriginX,
                    y: screenRect.minY - windowOriginY,
                    width: screenRect.width,
                    height: screenRect.height
                ).insetBy(dx: -8, dy: -8) // small grace padding so edge clicks register
            case .closed, .popping:
                // When closed, use the indicator rect anchored top-right with hover padding
                let notchRect = geometry.deviceNotchRect
                let topOffset = geometry.menuBarHeight + NotchGeometry.topInset
                let rightInset = NotchGeometry.rightInset
                return CGRect(
                    x: geometry.screenRect.width - notchRect.width - rightInset - 10,
                    y: geometry.windowHeight - topOffset - notchRect.height - 5,
                    width: notchRect.width + 20,
                    height: notchRect.height + 10
                )
            }
        }

        self.view = hostingView
    }
}
