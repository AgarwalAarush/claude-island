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

        // Calculate the hit-test rect based on panel state
        hostingView.hitTestRect = { [weak self] in
            guard let self = self else { return .zero }
            let vm = self.viewModel
            let geometry = vm.geometry

            // Window coordinates: origin at bottom-left, Y increases upward.
            // The window is positioned at top of screen, so top-of-window = `windowHeight`.
            // The floating pill lives at `(screenMax - rightInset, screenMax - menuBarHeight - topInset)`
            // in screen coords, which maps to the same right-edge math in window coords.
            let windowHeight = geometry.windowHeight
            let screenWidth = geometry.screenRect.width
            let topOffset = geometry.menuBarHeight + NotchGeometry.topInset
            let rightInset = NotchGeometry.rightInset

            switch vm.status {
            case .opened:
                let panelSize = vm.openedSize
                let panelWidth = panelSize.width + 52  // Account for corner radius padding
                let panelHeight = panelSize.height
                return CGRect(
                    x: screenWidth - panelWidth - rightInset,
                    y: windowHeight - topOffset - panelHeight,
                    width: panelWidth,
                    height: panelHeight
                )
            case .closed, .popping:
                // When closed, use the indicator rect anchored top-right with hover padding
                let notchRect = geometry.deviceNotchRect
                return CGRect(
                    x: screenWidth - notchRect.width - rightInset - 10,
                    y: windowHeight - topOffset - notchRect.height - 5,
                    width: notchRect.width + 20,
                    height: notchRect.height + 10
                )
            }
        }

        self.view = hostingView
    }
}
