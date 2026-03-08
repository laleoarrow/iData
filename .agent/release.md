# Release and publishing

## Build the app

```bash
cd /Users/leoarrow/Project/mypackage/agents/iData
./scripts/build_app.sh
```

Output:

- `dist/iData.app`

## Build a GitHub release asset

```bash
cd /Users/leoarrow/Project/mypackage/agents/iData
./scripts/package_release.sh 0.1.4
```

Outputs:

- `dist/iData-v0.1.4-macos-universal.zip`
- `dist/iData-v0.1.4-macos-universal.dmg`
- `dist/iData-v0.1.4-macos-universal.pkg`
- `dist/SHA256SUMS.txt`
- `docs/appcast.xml`

## Build only the installer package

```bash
cd /Users/leoarrow/Project/mypackage/agents/iData
./scripts/build_app.sh
./scripts/create_pkg.sh 0.1.4
```

Installer behavior:

- installs `iData.app` into `/Applications/iData.app`
- writes VisiData follow-up guidance into `/Users/Shared/iData`
- places an interactive helper at `/Users/Shared/iData/Configure VisiData.command`
- keeps `VisiData` external; users are guided toward `pipx install visidata` and `pipx inject visidata openpyxl`

## Publish with GitHub CLI

Create repo:

```bash
gh repo create iData --public --source=. --remote=origin --push
```

Create tag:

```bash
git tag v0.1.4
git push origin main --tags
```

Create release:

```bash
gh release create v0.1.4 \
  dist/iData-v0.1.4-macos-universal.zip \
  dist/iData-v0.1.4-macos-universal.dmg \
  dist/iData-v0.1.4-macos-universal.pkg \
  dist/SHA256SUMS.txt \
  --title 'v0.1.4' \
  --notes-file docs/releases/v0.1.4.md
```

## Distribution notes

- The app is currently unsigned and not notarized
- Local installs from the working tree can be copied directly into `/Applications`
- Users who download from GitHub may need to approve the app in macOS security settings
- Sparkle requires `docs/appcast.xml` to be published from GitHub Pages
