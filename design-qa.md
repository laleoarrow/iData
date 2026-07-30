# iData UI design QA

## Comparison setup

- Appearance: Chinese, dark mode.
- Build: Release `0.2.10` (build 30), installed at `/Applications/iData.app`.
- Source: the user-annotated `0.2.9` welcome screenshot, normalized to the implementation screenshot size of 1856 × 1360 px.
- Implementation: the installed Release app at the 860 × 612 pt minimum window, expanded sidebar, and matching recent-file state.
- The complete source and implementation windows were compared side by side at the same aspect ratio.
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
- Settings and Tutorial were intentionally left unchanged.

## Visual review

- Typography: the selected title, subtitle, shortcut labels, status, and version hierarchy is preserved.
- Spacing: hero, divider, shortcut grid, and footer follow the selected concept without nested cards.
- Color: the background capture shows the inactive native button state; the primary action uses the normal blue accent when the window is active.
- Controls: Open and More remain compact native macOS controls with balanced heights and no oversized CTA.
- Narrow layout: all four shortcuts fit the 860 × 612 pt minimum window without clipping or unwanted wrapping.

## Verification scope

- The annotated reference exposed a P2 empty-space and overlong-divider issue.
- The `0.2.10` capture shows readiness directly below the shortcut grid and the center divider ending with the second shortcut row; no P0, P1, or P2 visual differences remained.
- Verified the installed Release build, minimum-window relayout, sidebar styling, compact actions, overflow contents, localization, and shortcut layout.
- Drag-and-drop was intentionally not tested at the user’s request.

final result: passed
