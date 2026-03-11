# Terminal Layout Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate first-frame table clipping and horizontal misalignment in the embedded VisiData terminal.

**Architecture:** Keep the native Swift bridge intact and fix the rendering contract inside `terminal.html`. Separate the styled shell from the xterm mount point, make layout measurement follow xterm's official fit logic more closely, and force a redraw-sized resize when focus/visibility stabilizes so VisiData repaints even when the terminal size has not numerically changed.

**Tech Stack:** Swift 6, Swift Testing, WKWebView, xterm.js

---

### Task 1: Lock failing browser bridge regressions

**Files:**
- Modify: `Tests/iDataAppTests/EmbeddedTerminalViewTests.swift`
- Read: `iDataApp/Resources/TerminalAssets/terminal.html`

**Step 1: Write the failing tests**

- Add a WKWebView-backed test that loads `terminal.html`, records `idata` bridge messages, and asserts `window.iDataFocusTerminal()` emits a fresh `resize` message even when the frame size did not change.
- Add a DOM layout test that asserts the xterm viewport and screen share the same top-left origin after the page stabilizes.

**Step 2: Run test to verify it fails**

Run: `swift test --filter EmbeddedTerminalViewTests`
Expected: FAIL because focus does not currently force another resize and the current DOM uses offset origins.

### Task 2: Fix the terminal frontend layout contract

**Files:**
- Modify: `iDataApp/Resources/TerminalAssets/terminal.html`

**Step 1: Isolate xterm from decorative padding**

- Introduce a dedicated mount element inside `#terminal` so xterm opens into an undecorated box.
- Move visual padding to the outer shell/container instead of `.xterm`.

**Step 2: Align fit logic with official xterm behavior**

- Base width/height calculations on the xterm element parent and subtract scrollbar/padding consistently.
- Keep retry-based layout passes, but let specific events request one forced resize even when `cols x rows` is unchanged.

**Step 3: Trigger redraws when visibility/focus stabilizes**

- Make `window.iDataFocusTerminal()` request a forced layout pass.
- Add focus/visibility/page-show hooks that request the same one-shot forced resize.

### Task 3: Verify native bridge still behaves correctly

**Files:**
- Modify only if needed: `Sources/iData/EmbeddedTerminalView.swift`
- Re-run: existing tests covering ready/rebind behavior

**Step 1: Confirm no extra native changes are required**

- Only touch the Swift bridge if the JS contract changes.

**Step 2: Run targeted and full verification**

Run: `swift test`
Run: `/bin/zsh -lc 'xcodebuild -project iData.xcodeproj -scheme iDataApp -configuration Debug -derivedDataPath .build/xcode-debug build'`
Run: `./scripts/build_app.sh`

**Step 3: Manual runtime check**

- Open a wide sample table in the built app and capture a screenshot showing the corrected first render state.
