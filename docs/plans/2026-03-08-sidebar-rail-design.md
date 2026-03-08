# Sidebar rail design

## Goal

Refine the existing left sidebar without switching to an overlay drawer. The sidebar supports two states:

- Expanded: current-width sidebar with recent-file cards.
- Collapsed: narrow rail that still preserves access to history and utility actions.

The right-side VisiData content must always relayout instead of being covered by an overlay.

## Approved behavior

- Put the collapse / expand control in the top-right of the sidebar header area.
- Collapsed header shows only the app icon.
- Hovering the collapsed app icon swaps to an `x` affordance that clears all recent files.
- Collapsed history shows circular items containing the first letter of each file title.
- Hovering a collapsed history item reveals an `x` affordance for removal; normal click still reopens the file.
- Expanded recent-file titles show exactly one line and use middle truncation to preserve suffix visibility.
- Expanded footer actions (`Settings`, `Help`, `Tutorial`) show icon only, with no capsule background or label text; hover help provides the labels.
- Sidebar transitions should feel smooth and coordinated.
- Tutorial-related UI already in `ContentView.swift` should remain untouched outside sidebar-adjacent code.

## Implementation notes

- Add a persisted `isSidebarCollapsed` state in `AppModel`.
- Keep the root layout in `HStack` so the detail pane resizes naturally.
- Use coordinated spring animation for width and content opacity / scale.
- Keep changes focused on `ContentView.swift` and the minimal model state in `AppModel.swift`.

## Verification

- Add model tests for persisted sidebar collapse state.
- Run `swift test`.
- Run an `xcodebuild` macOS build as required by the project guide.
