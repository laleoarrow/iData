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
./scripts/package_release.sh 0.1.7
```

Outputs:

- `dist/iData-v0.1.7-macos-universal.zip`
- `dist/iData-v0.1.7-macos-universal.dmg`
- `dist/iData-v0.1.7-macos-universal.pkg`
- `dist/SHA256SUMS.txt`
- `docs/appcast.xml`

## Build only the installer package

```bash
cd /Users/leoarrow/Project/mypackage/agents/iData
./scripts/build_app.sh
./scripts/create_pkg.sh 0.1.7
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
git tag v0.1.7
git push origin main --tags
```

Create release:

```bash
gh release create v0.1.7 \
  dist/iData-v0.1.7-macos-universal.zip \
  dist/iData-v0.1.7-macos-universal.dmg \
  dist/iData-v0.1.7-macos-universal.pkg \
  dist/SHA256SUMS.txt \
  --title 'v0.1.7' \
  --notes-file docs/releases/v0.1.7.md
```

## Update Appcast & Website (Crucial Step)

The iData website at `https://laleoarrow.github.io/iData/` serves the `appcast.xml` for seamless Sparkle over-the-air updates. During a release:

1. `package_release.sh` regenerates `docs/appcast.xml`.
2. You **must commit and push** this file to the `main` branch.
3. Once pushed, GitHub Pages will automatically publish the changes under `/docs`.
4. Ensure you perform: `git add docs/appcast.xml && git commit -m "chore: update appcast for vXXX" && git push`

## Distribution notes

- The app is currently unsigned and not notarized
- Local installs from the working tree can be copied directly into `/Applications`
- Users who download from GitHub may need to approve the app in macOS security settings
- Sparkle requires `docs/appcast.xml` to be published from GitHub Pages
