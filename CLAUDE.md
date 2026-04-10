# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Claude Island is a macOS menu bar app (Swift/SwiftUI, macOS 15.6+) that renders a floating Dynamic Island–style overlay to monitor Claude Code CLI sessions, surface permission approval prompts, and show chat history. It ships as an accessory-policy app with no Dock icon.

The overlay is anchored to the **top-right corner of the screen**, 8pt below the menu bar and 8pt from the right edge. It is always visible as a small rounded pill and expands leftward + downward when activity occurs or the user clicks/hovers it. (It originally lived in the MacBook notch — the codebase still has `NotchShape.swift`, `NotchPanel`, etc. as legacy names from that era.)

## Keeping this file in sync

**Update CLAUDE.md within every feature, not after.** Whenever you add, remove, or meaningfully change behavior in this repo, edit the relevant section of this file *as part of the same change* (architecture sections, gotchas, build commands, conventions). After completing a feature, do a final pass to ensure the file still describes reality. Stale guidance here costs future sessions far more time than it saves. Treat this file as production code: if a description here is wrong, fix it the moment you notice — don't defer.

When in doubt about whether a change warrants a CLAUDE.md update, ask: "would a future instance reading this file get a wrong mental model after my change?" If yes, update it.

## Commit frequently, in small focused commits

**Commit immediately after every completed change — do not wait to be asked.** When working through multiple issues or implementing a multi-step feature, commit each meaningful step independently rather than batching them. Examples: a behavior fix is its own commit; the test for that fix can be in the same commit; a separate refactor goes in its own commit. Avoid sweeping "WIP" commits that mix unrelated changes. Pre-existing local config (signing identity, bundle ID, Info.plist key migration, etc.) does NOT belong in feature commits — leave those unstaged for the user to handle separately.

Commit message style in this repo is short imperative present-tense titles, no body unless necessary (see `git log --oneline`). Examples: "Move overlay to top-right corner with always-visible idle crab", "Fix Mixpanel assertion on single-instance early-terminate". Add a `Co-Authored-By` trailer when authored by Claude.

**Backlog lives in `ISSUES.md` at the repo root** (tracked in git). When closing an issue, move it from the Open section to Closed with the commit SHA that fixed it — don't delete the entry.

## Testing

There is **no Xcode test target** in this project. Tests live as standalone Swift files under `Tests/` and are compiled + run via `./scripts/test.sh`, which uses `swiftc` to build each test file together with the production source files it covers, then executes the resulting binary. Each test file is its own executable that exits non-zero on first failure.

The test runner uses tiny inline assertion helpers (`assertEqual`, `assertTrue`, etc.) — there's no XCTest dependency, no project surgery required, and tests can be run from CI or a plain shell with no Xcode-specific tooling.

**What to test here:** pure logic — `NotchGeometry` math, `NotchViewModel` state transitions (where they don't depend on `EventMonitors` or `NSEvent`), constants like hover delay, conversion helpers in `MCPToolFormatter` / `SessionPhaseHelpers`, hook-event normalization, anything in `Models/`. **What NOT to test here:** SwiftUI rendering, real `NSEvent` handling, window positioning at the AppKit layer, anything involving the file system or sockets — those would need either UI tests or integration tests with real Claude Code, both out of scope for this layer.

When fixing a bug, **add a failing test for it first** (or alongside the fix, if the test infrastructure isn't ready for that scenario). When adding a new pure-logic helper, add a test for it in the same commit. Run `./scripts/test.sh` before every commit to confirm nothing regressed.

Filter to a single test file with `./scripts/test.sh NotchGeometry` (substring match against the `*Tests.swift` filename). Adding a new test file means adding an entry to the `TEST_SOURCES` array in `scripts/test.sh` mapping the test file to the production source file(s) it covers.

## Build / Run

```bash
# Open in Xcode
open ClaudeIsland.xcodeproj

# Debug build from CLI
xcodebuild -scheme ClaudeIsland -configuration Debug build

# Release build
xcodebuild -scheme ClaudeIsland -configuration Release build

# Full release pipeline (archive + export, signed, Developer ID)
./scripts/build.sh

# Notarize + DMG + Sparkle appcast
./scripts/create-release.sh
```

There is no test target in the Xcode project. Dependencies (Mixpanel, Sparkle) are managed via Swift Package Manager and resolved by Xcode automatically.

**Before re-running from Xcode:** hitting Stop only detaches the debugger — the accessory-policy app process keeps running. Run `pkill -f "Claude Island"` (or kill the PID shown by `ps aux | grep "[C]laude Island"`) before re-launching, or the `ensureSingleInstance` check in `AppDelegate` will silently terminate your new build.

## Architecture

The app has three cooperating subsystems: **hook ingestion**, **central session state**, and **notch UI**. Understanding their boundaries is key before editing.

### 1. Hook ingestion (how events get in)

- On launch, `HookInstaller` (`Services/Hooks/HookInstaller.swift`) copies `Resources/claude-island-state.py` into `~/.claude/hooks/` and merges entries into `~/.claude/settings.json` for every hook event (`PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`, `SessionStart`, `PreCompact`, etc.). It detects existing hooks by substring-matching `claude-island-state.py` so it won't double-register.
- Claude Code invokes the Python hook for each event. The hook connects to a Unix domain socket at `/tmp/claude-island.sock` and sends JSON. On remote (SSH) hosts where that path doesn't exist, the hook falls back to TCP `127.0.0.1:9876` — sshd's `RemoteForward 9876 /tmp/claude-island.sock` republishes the Mac's unix socket as a loopback TCP listener on the remote. TCP is used for the remote leg specifically because unix-socket forwarding leaves stale `/tmp/claude-island.sock` files behind on ungraceful disconnect (laptop sleep, network drop), which silently break every subsequent `RemoteForward` until the file is removed; fixing that properly requires `StreamLocalBindUnlink yes` in the remote's sshd_config, which needs root. TCP listeners self-clean. The Mac side (`HookSocketServer`) is unaware of any of this — it only ever listens on the unix socket. For `PermissionRequest`, the hook **blocks** waiting for the app to write back an approve/deny decision (up to 5 min). The hook timeout in `settings.json` is set to 86400s for permission requests specifically.
- `HookSocketServer` (`Services/Hooks/HookSocketServer.swift`) hosts that socket, decodes `HookEvent`, and forwards into the central store.
- In parallel, `Services/Session/ClaudeSessionMonitor` + `ConversationParser` + `JSONLInterruptWatcher` + `AgentFileWatcher` tail the JSONL transcripts under `~/.claude/projects/<project>/*.jsonl` to reconstruct chat history and catch things hooks don't report (e.g. user interrupts). Files prefixed `agent-` are subagent streams and handled separately.

### 2. Central state (`SessionStore`)

`Services/State/SessionStore.swift` is a Swift `actor` and the **single source of truth** for all sessions. All mutations flow through `process(_ event: SessionEvent)` — do not mutate session state elsewhere. It exposes a nonisolated Combine publisher (`sessionsPublisher`) for SwiftUI.

Related helpers in `Services/State/`:
- `ToolEventProcessor` — normalizes tool-use pre/post pairs from hook events.
- `FileSyncScheduler` — debounces (100ms) persistent writes of per-session state so we don't thrash disk on bursty hook streams.

Models live in `Models/` (`SessionState`, `SessionPhase`, `SessionEvent`, `ChatMessage`, `ToolResultData`). `SessionPhase` drives UI state (idle / running / waiting-for-approval / compacting / etc.) — it is derived in `HookEvent.sessionPhase` and in `SessionPhaseHelpers`.

`SessionState.displayTitle` falls back through `conversationInfo.summary → conversationInfo.firstUserMessage → projectName`. Both `summary` and `firstUserMessage` are extracted by `ConversationParser` from the JSONL transcript, which calls `ConversationTextFilter.extractUserText(from:)` to skip slash-command wrapper messages (e.g. `<command-message>init</command-message>`) and handle the array-form content blocks Claude Code emits for expanded slash-command prompts. If you touch title derivation, edit `Services/Session/ConversationTextFilter.swift` and add a case in `Tests/ConversationTextFilterTests.swift` — it's a pure enum with no dependencies, so it compiles cleanly in the standalone test runner.

### 3. Overlay UI (top-right floating pill)

- `App/AppDelegate.swift` is the real entrypoint. `ClaudeIslandApp.swift` only declares an empty `Settings` scene because the app uses a fully custom `NSWindow`. AppDelegate enforces single-instance, **initializes Mixpanel in `init()` (not `applicationDidFinishLaunching`)** so the early-terminate path in `ensureSingleInstance` can't trip Mixpanel's "must initialize first" assertion during `applicationWillTerminate`, then starts Sparkle and installs hooks.
- `App/WindowManager` + `UI/Window/NotchWindow*` build a borderless, always-on-top, non-activating `NSPanel` that spans the **full screen width × full visible screen height** (`max(750, screenFrame.height - menuBarHeight)`). The window is intentionally oversized — the SwiftUI `NotchView` positions itself within this window via conditional alignment + padding keyed off `viewModel.panelAnchor`: `.topTrailing` with `.padding(.top, menuBarHeight + 8) .padding(.trailing, 8)` for most modes, `.center` with zero padding for the plan viewer. The passthrough hit-test in `UI/Window/NotchViewController.swift` (`PassThroughHostingView.hitTest`) gates mouse events to just the actual content rect so clicks elsewhere fall through to whatever's behind.
- `Core/NotchGeometry` computes the screen-coordinate hit rects for the closed pill and the opened panel. Corner-anchored rects use `screenRect.maxX - rightInset` / `screenRect.maxY - menuBarHeight - topInset`; center-anchored rects use `screenRect.midX / midY`. `topInset` and `rightInset` are both `8`. Menu bar height comes from `Ext+NSScreen.menuBarHeight` (= `frame.maxY - visibleFrame.maxY`), which works uniformly for notched (~38pt) and non-notched (~24pt) displays. **`panelScreenRect(for:anchor:)` is the single entry point** used by both `NotchView`'s SwiftUI layout and `NotchViewController`'s hit test, so corner/center math can't drift between them.
- `Core/NotchViewModel` is the SwiftUI-observable bridge between `SessionStore`'s publisher and the views in `UI/Views/` (`NotchView`, `ChatView`, `ClaudeInstancesView`, `NotchMenuView`, `PlanView`). `Core/NotchActivityCoordinator` decides when the pill expands its activity area based on session state. The view model exposes `panelAnchor` + `currentPanelScreenRect` — read these whenever you need to know where the opened panel actually lives; do not recompute the rect inline.
- **Timing/feel constants live in `Core/NotchTunables.swift`** (hover-to-open delay, mouse-leave close delay, etc.) — a deliberately dependency-free enum so they can be unit-tested in isolation. Adjust values there, not inline in `NotchViewModel`.
- User interaction flows through two `NotchViewModel` handlers: `handleMouseMove` drives the hover-open timer + mouse-leave close timer (both using `NotchTunables` delays), and `handleMouseDown` handles click-to-open and click-outside-to-close. A `NSHapticFeedbackManager.alignment` buzz fires inside `notchOpen` for user-initiated expansions (hover/click) but is skipped for `.boot` and `.notification` reasons so the app launch and auto-opens don't spam the trackpad.
- The pill is **always visible** as a small rounded pill (clipped via `RoundedRectangle(style: .continuous)`, not the legacy `NotchShape`). When idle it shows a centered Claude crab icon. When a session enters `.processing`, the pill expands leftward via the `headerRow` HStack growing naturally — `matchedGeometryEffect(id: "crab")` flies the crab from center to the left side as the spinner appears on the right. When opened (click/hover), content transitions use `.scale(scale: 0.8, anchor: .topTrailing)` so the panel appears to grow out of the closed pill's anchor point — except for the plan viewer, which anchors at `.center` instead.
- **`NotchContentType.plan(text:returnTo:)`** renders a full-screen-centered scrollable plan in `UI/Views/PlanView.swift` (reached by tapping the preview tile on an `ExitPlanMode` tool row in chat). The plan markdown is captured by value at tap time, so the viewer is decoupled from any later mutations — no new caches, actors, or async work. `NotchView` sets `.environmentObject(viewModel)` so `ExitPlanModeResultContent` in `ToolResultViews.swift` can reach `showPlan`/`exitPlan` without prop drilling. The `returnTo` associated value remembers whether to pop back to the originating chat or the instances list. When adding more center-anchored content types, add a case that sets `panelAnchor == .center` and give the content its own full-height header — `NotchView.contentProvidesOwnHeader` skips the floating pill's header row for those modes.
- `App/ScreenObserver` tears down and rebuilds the window on display changes. `Core/ScreenSelector` and `Core/SoundSelector` handle target-display + approval-sound selection, persisted via `Core/Settings.swift` (UserDefaults).
- `Services/Window/` (`WindowFinder`, `WindowFocuser`, `YabaiController`) is used to jump focus to the terminal running a given Claude session when the user taps a notification — including an optional Yabai integration path.

**Legacy naming:** the codebase still uses "notch" in many type names (`NotchView`, `NotchPanel`, `NotchGeometry`, `NotchShape`, `deviceNotchRect`, etc.) from when the overlay was tucked into the physical MacBook notch. These names are retained for compatibility and to keep diffs small — don't rename them piecemeal. The `NotchShape.swift` file is unused after the move but left in place.

### Cross-cutting

- **Logging:** `os.log` with subsystem `com.claudeisland` and per-area categories (`Hooks`, `Session`, …). Prefer this over `print`.
- **Analytics:** Mixpanel is initialized in `AppDelegate`. Events tracked today are limited to `App Launched` and session-start; distinct ID is the IOPlatformUUID (see `getOrCreateDistinctId`). Don't add event tracking that includes conversation content — the README explicitly promises none is collected.
- **Auto-update:** Sparkle `SPUUpdater` with a custom `NotchUserDriver` so update prompts render inside the notch instead of a standard Sparkle window. `scripts/generate-keys.sh` sets up the EdDSA signing key.

## Editing guidance specific to this repo

- When adding a new Claude Code hook event, update both `Resources/claude-island-state.py` (to forward it) and the `hookEvents` list in `HookInstaller.updateSettings` (to register it). `HookInstaller` is idempotent but only detects its own previous hook by substring — don't rename the Python script without updating the detection string in `installIfNeeded`, `isInstalled`, and `uninstall`.
- State changes must go through `SessionStore.process(_:)`. If you find yourself wanting to mutate a `SessionState` from a view or service, route a new `SessionEvent` case through the actor instead.
- Overlay positioning math is routed through a **single source of truth**: `NotchViewModel.currentPanelScreenRect` (which delegates to `NotchGeometry.panelScreenRect(for:anchor:)`). Both `UI/Views/NotchView.swift` (via `viewModel.panelAnchor` driving its alignment + padding) and `UI/Window/NotchViewController.swift` (converting the rect to window-local for the hit test) consume this property. If you add a new anchor or a new panel position, extend `panelScreenRect` and `panelAnchor` — do not inline corner/center math in the view or hit-test closure, or they'll drift. All corner-anchored rects use `topInset = 8` / `rightInset = 8` and the same `menuBarHeight`.
- `matchedGeometryEffect(id: "crab")` has **multiple potential sources** across `headerRow` (left side when activity), the centered idle position, and `openedHeaderContent`. Their `isSource:` conditions must remain mutually exclusive — if you add a new state where the crab is shown, ensure exactly one source is true at any time, or SwiftUI will pick one arbitrarily and the morph animation will jump.
- **`EventMonitor.start()` installs BOTH a global and a local NSEvent monitor.** That means `NotchViewModel.handleMouseDown` fires even for clicks inside our own app's windows, not just clicks elsewhere on the system. Any click-handling logic in `handleMouseDown` must not assume "this click is outside us" — always hit-test against the panel rect first. (This is how the three-dots menu button got broken pre-`732535f`: a stale toggle branch thought in-panel clicks were notch-toggle clicks and collapsed the panel on every header button press.)
- **Mixpanel must be initialized in `AppDelegate.init()`**, not `applicationDidFinishLaunching` — the single-instance guard returns early from `applicationDidFinishLaunching` but `applicationWillTerminate` still runs and calls `Mixpanel.mainInstance().flush()`. Initializing in `init()` is the only way to make every code path safe.
- **Killing a running instance during dev**: hitting Stop in Xcode does NOT kill the app process because it's an accessory-policy app with no Dock icon — the debugger detaches but the process keeps running. Use `pkill -f "Claude Island"` (or kill the PID directly) before re-running, or you'll hit `ensureSingleInstance` and silently launch nothing. Easy way to spot a stale build: `ps aux | grep "[C]laude Island"`.
- The window is intentionally **full screen width × full visible screen height** (with a 750pt floor). This is deliberate — the passthrough hit-test handles mouse filtering, and a full-size window simplifies state transitions (no window-resize jitter when the panel expands) and lets center-anchored modes like the plan viewer be vertically centered on the real screen. Don't shrink it to "match content" without understanding the hit-test pipeline.
- Bumping the release version means editing the Xcode project's `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` (see recent commits `Bump project version` / `Bump version to 1.2`) and then running `./scripts/create-release.sh` which produces the DMG and Sparkle appcast entry.
