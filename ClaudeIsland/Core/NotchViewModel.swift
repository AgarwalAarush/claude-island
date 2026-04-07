//
//  NotchViewModel.swift
//  ClaudeIsland
//
//  State management for the dynamic island
//

import AppKit
import Combine
import SwiftUI

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason {
    case click
    case hover
    case notification
    case boot
    case unknown
}

/// Where the plan viewer should return to when dismissed.
/// Captured at the moment the plan tile is tapped so we don't need a separate
/// "previous content" piece of state; it lives only while the plan is on screen.
enum ReturnTarget: Equatable {
    case instances
    case chat(SessionState)
}

enum NotchContentType: Equatable {
    case instances
    case menu
    case chat(SessionState)
    case stats
    /// Full-plan viewer anchored to the center of the screen.
    /// Carries the plan markdown by value (snapshot at tap time) plus where to return on dismiss.
    case plan(text: String, returnTo: ReturnTarget)

    var id: String {
        switch self {
        case .instances: return "instances"
        case .menu: return "menu"
        case .chat(let session): return "chat-\(session.sessionId)"
        case .stats: return "stats"
        case .plan: return "plan"
        }
    }
}

@MainActor
class NotchViewModel: ObservableObject {
    // MARK: - Published State

    @Published var status: NotchStatus = .closed
    @Published var openReason: NotchOpenReason = .unknown
    @Published var contentType: NotchContentType = .instances
    @Published var isHovering: Bool = false
    @Published var projectScanResults: [String: ProjectScanResult] = [:]

    // MARK: - Dependencies

    private let screenSelector = ScreenSelector.shared
    private let soundSelector = SoundSelector.shared

    // MARK: - Geometry

    let geometry: NotchGeometry
    let spacing: CGFloat = 12
    let hasPhysicalNotch: Bool

    var deviceNotchRect: CGRect { geometry.deviceNotchRect }
    var screenRect: CGRect { geometry.screenRect }
    var windowHeight: CGFloat { geometry.windowHeight }

    /// Dynamic opened size based on content type
    var openedSize: CGSize {
        switch contentType {
        case .chat:
            // Large size for chat view
            return CGSize(
                width: min(screenRect.width * 0.5, 600),
                height: 580
            )
        case .stats:
            return CGSize(
                width: min(screenRect.width * 0.5, 600),
                height: 500
            )
        case .menu:
            // Compact size for settings menu
            return CGSize(
                width: min(screenRect.width * 0.4, 480),
                height: 420 + screenSelector.expandedPickerHeight + soundSelector.expandedPickerHeight
            )
        case .instances:
            return CGSize(
                width: min(screenRect.width * 0.4, 480),
                height: 320
            )
        case .plan:
            // Full-plan viewer — centered on the screen, large enough to comfortably
            // read a multi-section markdown document without feeling cramped.
            return CGSize(
                width: min(screenRect.width * 0.6, 760),
                height: min(screenRect.height * 0.75, 720)
            )
        }
    }

    /// Where the currently-visible panel anchors on the screen.
    /// Plan viewer centers on the screen; everything else clings to the top-right.
    var panelAnchor: PanelAnchor {
        if case .plan = contentType { return .center }
        return .topTrailing
    }

    /// Current opened panel rect in screen coordinates, routed through `panelAnchor`.
    /// Single source of truth for both the SwiftUI layout and the hit-test pipeline.
    var currentPanelScreenRect: CGRect {
        geometry.panelScreenRect(for: openedSize, anchor: panelAnchor)
    }

    // MARK: - Animation

    var animation: Animation {
        .easeOut(duration: 0.25)
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private let events = EventMonitors.shared
    private var hoverTimer: DispatchWorkItem?
    private var mouseLeaveTimer: DispatchWorkItem?

    // MARK: - Initialization

    init(deviceNotchRect: CGRect, screenRect: CGRect, windowHeight: CGFloat, menuBarHeight: CGFloat, hasPhysicalNotch: Bool) {
        self.geometry = NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenRect,
            windowHeight: windowHeight,
            menuBarHeight: menuBarHeight
        )
        self.hasPhysicalNotch = hasPhysicalNotch
        setupEventHandlers()
        observeSelectors()
    }

    private func observeSelectors() {
        screenSelector.$isPickerExpanded
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        soundSelector.$isPickerExpanded
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Event Handling

    private func setupEventHandlers() {
        events.mouseLocation
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] location in
                self?.handleMouseMove(location)
            }
            .store(in: &cancellables)

        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleMouseDown()
            }
            .store(in: &cancellables)
    }

    /// Whether we're in chat mode (sticky behavior)
    private var isInChatMode: Bool {
        if case .chat = contentType { return true }
        return false
    }

    /// The chat session we're viewing (persists across close/open)
    private var currentChatSession: SessionState?

    private func handleMouseMove(_ location: CGPoint) {
        let inNotch = geometry.isPointInNotch(location)
        let inOpened = status == .opened && geometry.isPointInOpenedPanel(location, size: openedSize)

        let newHovering = inNotch || inOpened

        // Only update if changed to prevent unnecessary re-renders
        guard newHovering != isHovering else { return }

        isHovering = newHovering

        // Cancel any pending hover timer
        hoverTimer?.cancel()
        hoverTimer = nil

        // Mouse re-entered after a leave — cancel any pending close.
        if isHovering {
            mouseLeaveTimer?.cancel()
            mouseLeaveTimer = nil
        }

        // Start hover timer to auto-expand after the configured delay
        if isHovering && (status == .closed || status == .popping) {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isHovering else { return }
                self.notchOpen(reason: .hover)
            }
            hoverTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchTunables.hoverOpenDelay, execute: workItem)
        }

        // Mouse just left while the panel is open — schedule auto-close after a grace period.
        if !isHovering && status == .opened {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.isHovering, self.status == .opened else { return }
                self.notchClose()
            }
            mouseLeaveTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchTunables.mouseLeaveCloseDelay, execute: workItem)
        }
    }

    private func handleMouseDown() {
        let location = NSEvent.mouseLocation

        switch status {
        case .opened:
            // Click outside the panel → close (and re-post the click so it reaches whatever's behind us).
            // We deliberately do NOT have a "click the notch area to toggle close" branch here:
            // when the overlay was tucked into the physical notch, that branch let users click the
            // visible notch tab to dismiss the panel. With the top-right reposition, the notch rect
            // overlaps the opened panel's top-right header — including the three-dots menu button —
            // so the toggle branch was firing on every header button click and snapping the panel shut.
            if !currentPanelScreenRect.contains(location) {
                notchClose()
                repostClickAt(location)
            }
        case .closed, .popping:
            if geometry.isPointInNotch(location) {
                notchOpen(reason: .click)
            }
        }
    }

    /// Re-posts a mouse click at the given screen location so it reaches windows behind us
    private func repostClickAt(_ location: CGPoint) {
        // Small delay to let the window's ignoresMouseEvents update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Convert to CGEvent coordinate system (screen coordinates with Y from top-left)
            guard let screen = NSScreen.main else { return }
            let screenHeight = screen.frame.height
            let cgPoint = CGPoint(x: location.x, y: screenHeight - location.y)

            // Create and post mouse down event
            if let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseDown.post(tap: .cghidEventTap)
            }

            // Create and post mouse up event
            if let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseUp.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Actions

    func notchOpen(reason: NotchOpenReason = .unknown) {
        let wasClosed = (status != .opened)
        openReason = reason
        status = .opened

        // Fire a subtle haptic whenever the panel actually expands from a user action.
        // Skip the boot animation (too noisy at launch) and notification-triggered
        // opens (the app did that automatically, not the user).
        if wasClosed && reason != .boot && reason != .notification {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }

        // Don't restore chat on notification - show instances list instead
        if reason == .notification {
            currentChatSession = nil
            return
        }

        // Restore chat session if we had one open before
        if let chatSession = currentChatSession {
            // Avoid unnecessary updates if already showing this chat
            if case .chat(let current) = contentType, current.sessionId == chatSession.sessionId {
                return
            }
            contentType = .chat(chatSession)
        }
    }

    func notchClose() {
        // Save chat session before closing if in chat mode
        if case .chat(let session) = contentType {
            currentChatSession = session
        }
        status = .closed
        contentType = .instances
    }

    func notchPop() {
        guard status == .closed else { return }
        status = .popping
    }

    func notchUnpop() {
        guard status == .popping else { return }
        status = .closed
    }

    func toggleMenu() {
        contentType = contentType == .menu ? .instances : .menu
    }

    func showChat(for session: SessionState) {
        // Avoid unnecessary updates if already showing this chat
        if case .chat(let current) = contentType, current.sessionId == session.sessionId {
            return
        }
        contentType = .chat(session)
    }

    /// Go back to instances list and clear saved chat state
    func exitChat() {
        currentChatSession = nil
        contentType = .instances
    }

    func showStats() { contentType = .stats }

    func exitStats() { contentType = .instances }

    /// Open the full-plan viewer centered on the screen.
    /// The plan markdown is captured by value so the viewer is decoupled from any
    /// later mutation on the underlying chat item.
    func showPlan(text: String, returnTo: ReturnTarget) {
        contentType = .plan(text: text, returnTo: returnTo)
    }

    /// Dismiss the plan viewer and return to whatever the user was looking at.
    func exitPlan() {
        if case .plan(_, let target) = contentType {
            switch target {
            case .instances:
                contentType = .instances
            case .chat(let session):
                contentType = .chat(session)
            }
        }
    }

    func triggerProjectScans(for cwds: [String]) {
        Task { [weak self] in
            guard let self else { return }
            for cwd in cwds {
                if let r = await ProjectAnalyzer.shared.scan(cwd: cwd) {
                    await MainActor.run { self.projectScanResults[cwd] = r }
                }
            }
        }
    }

    /// Perform boot animation: expand briefly then collapse
    func performBootAnimation() {
        notchOpen(reason: .boot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.openReason == .boot else { return }
            self.notchClose()
        }
    }
}
