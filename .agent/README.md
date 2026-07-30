# iData agent docs

Use these files when working on `iData`:

- [`project.md`](project.md) — architecture, important files, supported formats, and dependency model
- [`debugging.md`](debugging.md) — runtime diagnosis, required handoff checks, and reproducible performance regression checks
- [`release.md`](release.md) — installable builds, GitHub releases, Sparkle, and Homebrew sync

Recommended reading order:

1. [`project.md`](project.md)
2. [`debugging.md`](debugging.md)
3. [`release.md`](release.md)

For performance-only work, define a before/after measure first and use the
performance regression section in `debugging.md`; UI and interaction behavior
remain invariants.
