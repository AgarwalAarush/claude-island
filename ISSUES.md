# Issues Log

## Open

### 1. Hover-to-expand: 0.3s delay + haptic feedback
Hovering over the closed pill should auto-expand it after **0.3 seconds** of sustained hover. The current code already has hover-to-expand wired up, but the delay is 1.0s which feels broken (users assume hover doesn't work). When the auto-expand fires, also play a slight haptic feedback (`NSHapticFeedbackManager.alignment` or similar).

**Files:** `Core/NotchViewModel.swift` (`handleMouseMove`).

### 2. "Three-dots" expanded-view button collapses immediately
Clicking the three-dots (hamburger) button in the corner of the opened panel — intended to switch to the menu view — causes the panel to collapse instead. **Root cause confirmed:** `handleMouseDown` in `NotchViewModel.swift:185` has an `else if geometry.notchScreenRect.contains(location)` branch that closes the panel when the user clicks "the notch area while the panel is open". With the top-right reposition, the notch rect now overlaps the opened panel's top-right corner — exactly where the three-dots button lives. The button click registers as a notch-area click and collapses.

**Fix:** remove the toggle-on-notch-click branch entirely (it was useful when the notch was in the screen center; it's harmful now).

**Files:** `Core/NotchViewModel.swift` (`handleMouseDown`).

### 3. Chat row click target too small
In the chat list, only the small "chat bubble" icon button opens the chat. The whole row should be a click target. Currently `InstanceRow` uses `.onTapGesture(count: 2)` (double-tap) — change to single tap so a single click anywhere on the row opens the chat.

**Files:** `UI/Views/ClaudeInstancesView.swift` (`InstanceRow.body`).

### 4. Auto-collapse when mouse leaves
When the panel is opened and the mouse moves outside its bounds, the panel should automatically collapse after a short grace period. Currently it stays open until the user clicks outside. The `handleMouseMove` already tracks `isHovering`; add a close timer when `isHovering` flips to false in `.opened` state.

**Files:** `Core/NotchViewModel.swift` (`handleMouseMove`).

## Investigation requirement (meta)
Before fixing any issue: do not take the report at face value. Read the relevant code paths and confirm the actual behavior and root cause before making changes. Add a regression test for each fix where the logic is testable (geometry math, state transitions, constants). UI rendering and real mouse events are out of scope for unit tests.

## Closed

(none yet)
