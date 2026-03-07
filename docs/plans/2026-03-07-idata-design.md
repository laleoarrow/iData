# iData Design

Date: 2026-03-07

## Goal

Build `iData`, a modern macOS shell around `VisiData`, so large table files can be opened with a native macOS experience while preserving `VisiData` behavior and shortcuts.

## User Requirements

- Project path: `/Users/leoarrow/Project/mypackage/agents/iData`
- Product name: `iData`
- Initial distribution: GitHub release, not Mac App Store
- Core table interaction must use `VisiData`
- UI should feel like a clean native macOS app
- File opening should fit macOS habits, including double-click / “Open With”

## Constraints

- `VisiData` is already installed locally at `/Users/leoarrow/.local/bin/vd`
- The current workspace is not a git repository, so git worktree flow does not apply
- No embedded terminal library is preinstalled locally
- Without a terminal emulator component, a true embedded `VisiData` viewport is not realistic in the first implementation slice

## Architecture

### Core split

1. `iDataCore`
   - Pure Swift logic for locating `vd`
   - Building safe shell commands / launch scripts
   - Managing recent files

2. `iData`
   - SwiftUI macOS shell app
   - Welcome screen, open panel, recent files, preferences
   - File-open handling for associated document types
   - Launch adapter for opening `VisiData`

### Launch strategy

The long-term target is:

- native shell window
- embedded terminal host
- `VisiData` rendered inside the app window

The first implementation slice uses a compatibility adapter:

- native shell app handles file association and file picking
- opening a file launches `VisiData` in Terminal
- the code is structured so the launch adapter can later be swapped for an embedded terminal host

This keeps `VisiData` behavior intact while avoiding a fake or incomplete terminal implementation.

## v1 Scope

- Native macOS app entry point
- Welcome screen with open action and recent files
- Preferences for explicit `vd` path
- Open file through `NSOpenPanel`
- Handle external file open events
- Record and show recent files
- Launch `VisiData` for the chosen file
- Bundle script to assemble `iData.app`
- File association metadata for common delimited text formats

## Recent Files UX

- The sidebar recent-files list is a lightweight launcher, not a file manager
- Hovering a recent item reveals a trailing close control
- Clicking the close control removes only the stored recent record
- Removing a recent item does not delete the underlying file and does not force-close the current `VisiData` session

## Out of Scope

- Reimplementing a table renderer
- Changing `VisiData` shortcuts or internal behavior
- App Store packaging
- Built-in plugin manager
- Full embedded terminal emulation in this first slice

## Validation Plan

- Unit tests for executable resolution, recent-file logic, and shell escaping
- Build the Swift package
- Build the `.app` bundle with a packaging script

## Official References

- Apple: Defining file and data types for your app
- Apple: Configuring the macOS App Sandbox
- Apple: App Store Review Guidelines
- Apple: Bundle Programming Guide / Info.plist document types
- VisiData: official site and usage docs
