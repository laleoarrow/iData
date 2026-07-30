# iData UI design QA

## Comparison setup

- Appearance: Chinese, dark mode.
- Build: Release `0.2.8` (build 28), installed at `/Applications/iData.app`.
- Welcome, Settings, and Help were compared in temporary side-by-side images at matching states.
- The temporary PNG evidence was removed after review so it does not ship in the repository.
- Interaction method: background launch plus targeted accessibility actions; the foreground app, pointer, and keyboard focus were not changed.

## Findings and resolutions

- Welcome: repeated hero, action rows, tutorial card, system card, and format card were competing for attention.
  Resolution: one opening task, one overflow menu, a flat shortcut reference, and one compact readiness row.
- Settings: decorative hero and stacked non-interactive cards made basic preferences feel like a dashboard.
  Resolution: native macOS tabs and grouped forms for General, Files, VisiData, and Updates.
- Help: the long stack required scrolling and repeated app identity.
  Resolution: topic navigation with one concise article visible at a time.
- Tutorial: chapter cards repeated the same controls and consumed excessive vertical space.
  Resolution: chapter navigation on the left and the selected lesson on the right.
- Sidebar: custom scroll rail, card rows, glow, and layout animation added cost without clarifying state.
  Resolution: native scrolling, flat rows, a single action menu, and instant width changes.
- Session: the shortcut panel covered the terminal and the toolbar exposed too many peer actions.
  Resolution: the tip is now above the terminal; Open remains visible and secondary actions move to a menu.
- Status and handoff notices: layered gradients and hover shadows made read-only information look interactive.
  Resolution: compact, single-layer banners with explicit actions only.
- Chinese copy: redundant explanations and English command labels were present.
  Resolution: shorter task-oriented Chinese and localized update/session menus.

## Visual review

- Typography: hierarchy is clear and uses native macOS sizes; no oversized decorative title remains outside the primary task.
- Spacing: consistent 8–20 pt rhythm; large empty card interiors and card-within-card stacks were removed.
- Color: accent color now marks actions, selection, and status rather than decorating every container.
- Controls: interactive format tiles remain visibly clickable; read-only status no longer animates on hover.
- Narrow layout: welcome content fits the 860 × 612 pt minimum window without clipping.

## Verification scope

- Compared before/after images for Welcome, Settings, and Help in a single side-by-side view.
- Inspected the Files settings tab at the installed Release build.
- Verified sidebar collapse logic, native scrolling, menu localization, and session layout in source tests.
- Drag-and-drop was intentionally not tested at the user’s request.

final result: pass
