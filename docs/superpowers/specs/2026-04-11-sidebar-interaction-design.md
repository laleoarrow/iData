# Sidebar Interaction Design

## Goal

Improve the macOS sidebar so recent-file interactions feel reliable under fast switching, resizing, and hover-heavy desktop usage.

## Approved Direction

1. Expand the primary hit target for each expanded recent-file row to the full card.
2. Keep pin/remove as trailing overlay actions so accessory controls do not steal the main row affordance.
3. Replace fragile hover-only SwiftUI event handling with a minimal `NSViewRepresentable` tracking bridge for sidebar hover state.
4. Add a yellow/blue gradient hover halo to sidebar buttons and recent-file affordances.
5. Preserve the current in-progress terminal/session stability work and verify the combined behavior with tests plus full project builds.

## Design Notes

- SwiftUI remains the source of truth for row state, active session state, and visual styling.
- AppKit is used only for pointer tracking via `NSTrackingArea`, which is the smallest bridge that addresses the desktop hover limitation.
- The tracking view must never intercept clicks; it exists only to report pointer enter/exit and to resync hover state after layout or window changes.
- Recent file cards should reserve trailing space for accessory controls so the text layout does not shift when hover actions appear.

## Verification

- Source-structure tests assert the full-card primary button layout and the existence of the AppKit hover bridge plus yellow/blue halo colors.
- Full verification requires `swift test` and a Debug `xcodebuild` build after implementation.
