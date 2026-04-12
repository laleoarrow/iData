# iData agent guide

This project is a native macOS wrapper around `VisiData`.

## Read first

- Start with `.agent/README.md`.
- Use `.agent/project.md` for architecture and key files.
- Use `.agent/debugging.md` for runtime debugging and verification.
- Use `.agent/release.md` for packaging, GitHub publishing, Homebrew sync, and release steps.

## Project rules

- Keep `Release` as the installable build and `Debug` as the local development build.
- `Debug` and `Release` intentionally use different bundle identifiers so macOS does not route file-open events to the wrong running app.
- `VisiData` is an external dependency. If you change launch behavior, preserve a clear error path when `vd` is missing.
- Verify local changes with `swift test` and an `xcodebuild` macOS build before claiming success.
- Build the user-facing app bundle with `./scripts/build_app.sh`.
- If you add a feature or fix a bug, do a manual macOS pressure pass before claiming stability.
- That pressure pass must include repeated file switching, drag-and-drop into the app, resize/relayout checks, and fast interaction changes that can expose clipped content, tearing, stale frames, or incorrect visible regions.
- Before handing work off, run the local equivalent of the push workflow and make sure the git worktree is cleaned up so the intended tracked changes are the only remaining diff.
- After a successful installable build, replace `/Applications/iData.app` with the fresh `dist/iData.app`, launch the installed app, and leave it ready for human review unless the user says not to.
