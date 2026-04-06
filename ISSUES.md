# Issues Log

## Open

(none)

## Investigation requirement (meta)
Before fixing any issue: do not take the report at face value. Read the relevant code paths and confirm the actual behavior and root cause before making changes. Add a regression test for each fix where the logic is testable (geometry math, state transitions, constants). UI rendering and real mouse events are out of scope for unit tests.

## Closed

### 1. Hover-to-expand: 0.3s delay + haptic feedback — fixed in `8d947d6`, `4b6f18b`
Hover-to-expand was already wired up in `NotchViewModel.handleMouseMove`, but the delay was 1.0s which felt broken. Reduced to 0.3s via the new dependency-free `NotchTunables.hoverOpenDelay` constant (so it's unit-testable in isolation), and added `NSHapticFeedbackManager.alignment` inside the hover work item right before `notchOpen` so feedback fires only when the timer actually runs.

### 2. "Three-dots" button collapses panel — fixed in `732535f`
**Root cause:** `handleMouseDown` had an `else if geometry.notchScreenRect.contains(location)` branch that closed the opened panel when the user clicked inside the notch's screen rect. Holdover from when the notch sat in the screen center. After the top-right reposition, the notch rect overlaps the opened panel's top-right header — exactly where the three-dots button lives — so clicks on it registered as notch-tab clicks and snapped the panel shut. Fix: removed the branch entirely. The "click outside to close" path is unaffected (separate branch).

### 3. Chat row click target too small — fixed in `bdbf4fd`
`InstanceRow` used `.onTapGesture(count: 2)`, requiring a double-click on the row body. Changed to single tap. Internal `Button` children still take SwiftUI gesture priority for their own actions.

### 4. Auto-collapse when mouse leaves — fixed in `c7e9ff0`
Added a `mouseLeaveTimer` in `NotchViewModel` that schedules `notchClose()` after the new `NotchTunables.mouseLeaveCloseDelay` (0.4s) when `isHovering` flips to false in `.opened` state. The grace period is cancelled if the cursor re-enters before it fires, so brief edge crossings don't kill the panel.
