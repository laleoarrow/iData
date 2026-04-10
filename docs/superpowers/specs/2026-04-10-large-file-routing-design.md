# Large File Routing Design

## Goal

When macOS routes a supported file to `iData` because `iData` is the default handler for that format, `iData` should only take ownership of the file if the file is larger than 500 MB. Smaller files should be silently forwarded to a non-`iData` application such as Excel, WPS, or TextEdit.

## Scope

This change only affects files opened externally through Finder, drag-open, or Launch Services app routing into `iData`.

This change does not alter:

- the format association UI
- the supported suffix list
- the internal `VisiData` launch path for files that `iData` does open
- manual opening behavior from inside the app unless that path shares the same external-open entry point

## Requirements

### Functional behavior

1. If `iData` receives a file-open event for a regular file with a supported table-like suffix and the file size is greater than `500 * 1024 * 1024` bytes, `iData` should open the file normally with `VisiData`.
2. If the same kind of file is `<= 500 * 1024 * 1024` bytes, `iData` should silently forward the file to a non-`iData` application instead of opening an `iData` session.
3. Forwarding must explicitly target another application so the open request does not loop back into `iData`.
4. If forwarding succeeds, `iData` should avoid surfacing its main window.
5. If forwarding fails, `iData` should preserve a clear user-visible error path.
6. Unsupported items and non-regular files should continue to follow the current error path.

### Fallback app selection

When forwarding a small file away from `iData`, candidate selection should be:

1. a previously remembered non-`iData` default application for that file type, if present
2. Launch Services candidates for the content type, excluding `iData`
3. existing text fallback behavior for plain text when no stronger candidate exists

If no non-`iData` candidate can be found, `iData` should surface an actionable error rather than opening the file itself.

## Design

### Routing layer

The file-size gate belongs in the external-open routing path between `AppDelegate` and the current `AppModel.openExternalFile` implementation.

Reasoning:

- `AppDelegate` currently activates the app window before routing the file.
- Silent forwarding for small files requires deferring activation until after the routing decision.
- `AppModel.openExternalFile` should remain focused on opening an `iData` session once `iData` has decided to own the file.

### Proposed structure

1. Add a route decision layer that classifies an incoming external file as:
   - open in `iData`
   - forward to alternate app
   - reject with existing error path
2. Move window activation in `AppDelegate` so it happens only for the `open in iData` and visible-error cases.
3. Introduce a small abstraction around "open this file with this application URL" so the behavior is unit-testable without hard-wiring `NSWorkspace` into tests.
4. Reuse existing `FileTypeAssociation` helper logic for:
   - supported extension normalization
   - stored previous default app resolution
   - alternative application candidate discovery

### Size detection

Use file metadata from `URLResourceValues.fileSizeKey` or `fileAllocatedSizeKey`/`totalFileAllocatedSizeKey` fallback as needed. The threshold is exact and binary:

- open in `iData` only when size is strictly greater than 500 MiB
- forward when size is less than or equal to 500 MiB

If file size cannot be resolved for an otherwise valid regular file, default to keeping the request inside `iData` and surfacing any subsequent launch error through the current path. This avoids silently dropping open requests because of metadata ambiguity.

### Error handling

- If the file is not a regular supported file, keep the existing message path.
- If forwarding is required but no alternate app can be resolved, show an explicit message that `iData` could not find another application for the file type.
- If forwarding is attempted and `NSWorkspace` reports failure, show an explicit message that forwarding failed, including the target app name when available.
- If `iData` keeps ownership and `vd` is missing, keep the current `VisiData` missing guidance unchanged.

## Testing

Add tests before implementation to cover:

1. supported file larger than 500 MiB routes into `iData`
2. supported file exactly 500 MiB forwards away from `iData`
3. supported file smaller than 500 MiB forwards away from `iData`
4. forwarding chooses a non-`iData` app and does not mutate the active `iData` session
5. forwarding failure surfaces an error message
6. unresolved file size falls back to the existing `iData` open path
7. the app delegate does not eagerly activate the app for silently forwarded files

## Implementation notes

- `500 MB` here is implemented as `500 MiB` (`500 * 1024 * 1024` bytes) for deterministic behavior in code.
- The routing logic should be isolated enough that future thresholds or preferences can be added without touching session launch internals.
- Existing bundle identifier separation between Debug and Release must remain unchanged so Launch Services routing stays correct during local testing.

## Verification

After implementation:

1. run `swift test`
2. run a Debug macOS build with `xcodebuild`
3. manually verify that a supported small file is forwarded without an `iData` session taking over
4. manually verify that a supported large file still opens in `iData`
