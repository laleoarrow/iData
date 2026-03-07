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
./scripts/package_release.sh 0.1.0
```

Outputs:

- `dist/iData-v0.1.0-macos-universal.zip`
- `dist/SHA256SUMS.txt`

## Publish with GitHub CLI

Create repo:

```bash
gh repo create iData --public --source=. --remote=origin --push
```

Create tag:

```bash
git tag v0.1.0
git push origin main --tags
```

Create release:

```bash
gh release create v0.1.0 \
  dist/iData-v0.1.0-macos-universal.zip \
  dist/SHA256SUMS.txt \
  --title 'v0.1.0' \
  --notes-file docs/releases/v0.1.0.md
```

## Distribution notes

- The app is currently unsigned and not notarized
- Local installs from the working tree can be copied directly into `/Applications`
- Users who download from GitHub may need to approve the app in macOS security settings
