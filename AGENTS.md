# iData agent guide

This project is a native macOS wrapper around `VisiData`.

## Read first

- Start with `.agent/README.md`.
- Use `.agent/project.md` for architecture and key files.
- Use `.agent/debugging.md` for runtime debugging and verification.
- Use `.agent/release.md` for packaging, GitHub publishing, and release steps.

## Project rules

- Keep `Release` as the installable build and `Debug` as the local development build.
- `Debug` and `Release` intentionally use different bundle identifiers so macOS does not route file-open events to the wrong running app.
- `VisiData` is an external dependency. If you change launch behavior, preserve a clear error path when `vd` is missing.
- Verify local changes with `swift test` and an `xcodebuild` macOS build before claiming success.
- Build the user-facing app bundle with `./scripts/build_app.sh`.
