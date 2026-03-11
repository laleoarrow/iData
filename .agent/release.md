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
./scripts/package_release.sh 0.1.8
```

Outputs:

- `dist/iData-v0.1.8-macos-universal.zip`
- `dist/iData-v0.1.8-macos-universal.dmg`
- `dist/iData-v0.1.8-macos-universal.pkg`
- `dist/SHA256SUMS.txt`
- `docs/appcast.xml`

Homebrew tap is synced by GitHub Actions after a GitHub Release is published.

Optional signing and notarization inputs:

- `IDATA_DEVELOPER_ID_APP`
- `IDATA_DEVELOPER_ID_INSTALLER`
- `IDATA_NOTARY_KEYCHAIN_PROFILE`
- or `IDATA_NOTARY_KEY_PATH` + `IDATA_NOTARY_KEY_ID` + `IDATA_NOTARY_ISSUER`

## Build only the installer package

```bash
cd /Users/leoarrow/Project/mypackage/agents/iData
./scripts/build_app.sh
./scripts/create_pkg.sh 0.1.8
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
git tag v0.1.8
git push origin main --tags
```

Create release:

```bash
gh release create v0.1.8 \
  dist/iData-v0.1.8-macos-universal.zip \
  dist/iData-v0.1.8-macos-universal.dmg \
  dist/iData-v0.1.8-macos-universal.pkg \
  dist/SHA256SUMS.txt \
  --title 'v0.1.8' \
  --notes-file docs/releases/v0.1.8.md
```

After `gh release create`, workflow `sync-homebrew-cask.yml` updates `laleoarrow/homebrew-tap` (`Casks/idata.rb`) using the release zip digest.

Required repository secret in `laleoarrow/iData`:

- `HOMEBREW_TAP_TOKEN`: GitHub token with `contents:write` on `laleoarrow/homebrew-tap`

For Apple signing/notarization details:

- `docs/apple-signing-and-notarization.md`

## Update Appcast & Website (Crucial Step)

The iData website at `https://laleoarrow.github.io/iData/` serves the `appcast.xml` for seamless Sparkle over-the-air updates. During a release:

1. `package_release.sh` regenerates `docs/appcast.xml`.
2. You **must commit and push** this file to the `main` branch.
3. Once pushed, GitHub Pages will automatically publish the changes under `/docs`.
4. Ensure you perform: `git add docs/appcast.xml && git commit -m "chore: update appcast for vXXX" && git push`

## Distribution notes

- The app is currently unsigned and not notarized
- `package_release.sh` now supports optional signing/notarization when the required Apple env vars are configured
- Local installs from the working tree can be copied directly into `/Applications`
- Users who download from GitHub may need to approve the app in macOS security settings
- Sparkle requires `docs/appcast.xml` to be published from GitHub Pages
