# iData first-pass `.pkg` packaging design

## Goal

Add a macOS installer package that installs `iData.app` into `/Applications/iData.app` and leaves the user with a clear, low-risk path for configuring the external `VisiData` dependency via `pipx`.

## Chosen approach

Use a staged payload root plus `pkgbuild` and `productbuild`:

- payload installs only the signed-app-shaped artifact into `/Applications`
- a top-level `postinstall` script writes user-facing setup guidance into `/Users/Shared/iData`
- release packaging keeps the existing `.zip` and `.dmg` outputs and adds a parallel `.pkg`

This keeps the first pass small, avoids touching app UI code, and leaves room for later signing, notarization, or richer Installer UI resources.

## Post-install guidance

The package does not silently install Python dependencies. Instead it creates:

- `/Users/Shared/iData/VisiData Setup Guide.md`
- `/Users/Shared/iData/Configure VisiData.command`

Those guide users through:

1. installing `pipx`
2. running `pipx ensurepath`
3. running `pipx install visidata`
4. injecting `openpyxl` for Excel support with `pipx inject visidata openpyxl`
5. verifying `vd` discovery for `iData`

## Verification

Minimum verification for this first pass:

- build `dist/iData.app`
- build the new `.pkg`
- verify the package archive with `pkgutil --check-signature`
- expand the package and confirm the payload and `postinstall` resources exist
