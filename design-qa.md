# iData UI design QA

## Comparison setup

- Appearance: Chinese, dark mode.
- Build: Release `0.2.17` (build 37), installed at `/Applications/iData.app`.
- Source visual truth: `/var/folders/jc/p8qsvpfd6t71pngj51n4yvvh0000gn/T/codex-clipboard-9b454ea8-6dff-4271-8338-c9893ce38a06.png` (1366 × 997 px, annotated inactive state).
- Focused implementation evidence: `/tmp/idata-open-button-hover.png` (304 × 136 px at 2×, 152 × 68 pt rendered hover state).
- Source intent: the primary Open button needs a visible hover halo against its system-blue fill.
- Implementation: the installed Release app at the 680 × 460 pt minimum content size, expanded sidebar, and matching recent-file state.
- The implementation was reviewed at both the 960 × 620 pt default content size and the new minimum size.
- Density normalization: the source establishes full-view location and proportions; the focused 2× component render evaluates only the requested hover treatment at native button scale.
- Interaction method: background launch and window-ID capture; the foreground app, pointer, and keyboard focus were not changed.

## Findings and resolutions

- Welcome hierarchy: the selected concept uses one clear task, one primary Open action, and one compact overflow action.
  Resolution: retained native button proportions and removed competing welcome-page cards.
- Shortcut layout: the first implementation truncated the movement keys and wrapped the Select Rows description.
  Resolution: used two explicit columns with column-specific key widths and a bounded scale-down for long key sequences.
- Vertical balance: stretching the neutral state created an empty band between shortcuts and readiness.
  Resolution: removed the viewport-filling spacer so readiness follows the shortcut section naturally.
- Shortcut divider: the vertical separator inherited the stretched row height and continued through empty space.
  Resolution: constrained the two-column shortcut row to its intrinsic content height.
- Sidebar color: the fixed dark fill created an abrupt block against the shared window background.
  Resolution: made the sidebar transparent and kept only a subtle one-pixel separator.
- Window sizing: the 1180 × 760 pt default and 860 × 580 pt minimum made the welcome window consume too much screen space.
  Resolution: reduced the default content size to 960 × 620 pt and the minimum to 680 × 460 pt.
- Narrow-window shortcuts: the two-column shortcut grid could not remain legible at the new minimum width.
  Resolution: retained the approved two-column layout at normal widths and switched to one column automatically when space is limited.
- Interactive hover feedback: the shared modifier had been reduced to an empty implementation, removing feedback from actionable controls.
  Resolution: restored a restrained blue–cyan–violet gradient on interactive controls only.
- Sidebar coverage: the footer icons, collapse/expand controls, empty rail action, and recent-file rows were not all connected to the restored hover layer.
  Resolution: applied the same shape-matched conditional gradient to each actionable sidebar surface.
- Footer motion: Settings, Help, and Tutorial had been flattened to static symbols even though their lightweight motion helper remained available.
  Resolution: reconnected the existing one-shot gear rotation, help bounce, and tutorial-cap tilt without adding a timer or continuous pointer tracking.
- Primary-action contrast: the shared low-opacity gradient was perceptible on dark and translucent controls but disappeared visually over the system-blue Open button.
  Resolution: added a prominent variant with a brighter inner rim, restrained translucent fill, and a low-opacity 4 pt outer gradient halo without changing the native button size or pressed state.
- Hover performance: the former implementation animated scale, offset, blur-like shadows, and persistent decorative layers.
  Resolution: the gradient layer now exists only while hovered, updates only on pointer enter/exit, and uses no continuous location tracking, blur, shadow, or layout-affecting transform.

## Visual review

- Typography: the selected title, subtitle, shortcut labels, status, and version hierarchy is preserved.
- Spacing: hero, divider, shortcut grid, and footer follow the selected concept without nested cards.
- Color: the background capture shows the inactive native button state; the primary action uses the normal blue accent when the window is active.
- Controls: Open and More remain compact native macOS controls with balanced heights and no oversized CTA.
- Primary action: Open keeps its native prominent-button appearance and gains a clearly visible blue–cyan–violet rim only while hovered.
- Focused comparison: the rendered hover state preserves the compact 120 × 36 pt button body while the halo extends into the surrounding 16 pt evidence margin; no text, icon, or corner clipping is visible.
- Hover: interactive controls receive one subtle, shape-matched gradient layer; read-only status remains static.
- Footer icons: Settings rotates once, Help bounces, and Tutorial tilts when the pointer enters; all three return to their resting state when it leaves.
- Narrow layout: the shortcut list switches to one column and remains accessible through the existing welcome-page scroll view.

## Verification scope

- The annotated reference exposed a P2 window-sizing and resize-limit issue.
- The installed app window reached the 680 × 460 pt minimum content size (680 × 492 pt including the title bar) without horizontal clipping.
- The hover layer was rendered directly in the test target and verified to produce colored output only while visible.
- The focused implementation render confirms the halo extends beyond the blue fill; the hidden-state renderer remains transparent, so the full-view inactive layout is unchanged.
- Verified that sidebar hover state changes only at pointer boundaries and that the gradient path contains no continuous tracking, geometry reader, radial gradient, blur, or shadow.
- Drag-and-drop was intentionally not tested at the user’s request.

final result: passed
