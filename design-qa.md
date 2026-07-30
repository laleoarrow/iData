# iData UI design QA

## Comparison setup

- Appearance: Chinese, dark mode.
- Build: Release `0.2.12` (build 32), installed at `/Applications/iData.app`.
- Source: the user report that the subtle gradient hover halo disappeared after the earlier performance pass.
- Implementation: the installed Release app at the 680 × 460 pt minimum content size, expanded sidebar, and matching recent-file state.
- The implementation was reviewed at both the 960 × 620 pt default content size and the new minimum size.
- The temporary PNG evidence was removed after review so it does not ship in the repository.
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
- Hover performance: the former implementation animated scale, offset, blur-like shadows, and persistent decorative layers.
  Resolution: the gradient layer now exists only while hovered, updates only on pointer enter/exit, and uses no continuous location tracking, blur, shadow, or layout-affecting transform.
- Settings and Tutorial were intentionally left unchanged.

## Visual review

- Typography: the selected title, subtitle, shortcut labels, status, and version hierarchy is preserved.
- Spacing: hero, divider, shortcut grid, and footer follow the selected concept without nested cards.
- Color: the background capture shows the inactive native button state; the primary action uses the normal blue accent when the window is active.
- Controls: Open and More remain compact native macOS controls with balanced heights and no oversized CTA.
- Hover: interactive controls receive one subtle, shape-matched gradient layer; read-only status remains static.
- Narrow layout: the shortcut list switches to one column and remains accessible through the existing welcome-page scroll view.

## Verification scope

- The annotated reference exposed a P2 window-sizing and resize-limit issue.
- The installed `0.2.11` window reached the 680 × 460 pt minimum content size (680 × 492 pt including the title bar) without horizontal clipping.
- The hover layer was rendered directly in the test target and verified to produce colored output only while visible.
- Verified that the hover path contains no continuous tracking, geometry reader, radial gradient, blur, shadow, scale, or offset; no P0, P1, or P2 visual differences remained.
- Drag-and-drop was intentionally not tested at the user’s request.

final result: passed
