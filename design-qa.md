# iData UI design QA

## Comparison setup

- Appearance: Chinese, dark mode.
- Build: Release `0.2.9` (build 29), installed at `/Applications/iData.app`.
- Source: the user-selected welcome concept, normalized to the implementation screenshot size of 1856 × 1360 px.
- Implementation: the installed Release app at the 860 × 612 pt minimum window, expanded sidebar, and matching recent-file state.
- The complete source and implementation windows were compared side by side at the same aspect ratio.
- The temporary PNG evidence was removed after review so it does not ship in the repository.
- Interaction method: background launch and window-ID capture; the foreground app, pointer, and keyboard focus were not changed.

## Findings and resolutions

- Welcome hierarchy: the selected concept uses one clear task, one primary Open action, and one compact overflow action.
  Resolution: retained native button proportions and removed competing welcome-page cards.
- Shortcut layout: the first implementation truncated the movement keys and wrapped the Select Rows description.
  Resolution: used two explicit columns with column-specific key widths and a bounded scale-down for long key sequences.
- Vertical balance: the first implementation placed readiness too close to the shortcut section.
  Resolution: let the neutral state expand to the viewport and anchored readiness near the bottom while keeping errors directly below it.
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

- Iteration 1 found key truncation, text wrapping, and a high readiness row.
- Iteration 2 matched the selected concept with those P2 issues resolved; no P0, P1, or P2 visual differences remained.
- Verified the installed Release build, minimum-window relayout, sidebar styling, compact actions, overflow contents, localization, and shortcut layout.
- Drag-and-drop was intentionally not tested at the user’s request.

final result: passed
