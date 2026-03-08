#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:-0.1.4}
APP_DIR="$ROOT_DIR/dist/iData.app"
PKG_NAME="iData-v${VERSION}-macos-universal.pkg"
FINAL_PKG="$ROOT_DIR/dist/$PKG_NAME"
PKG_WORK_DIR="$ROOT_DIR/dist/pkg"
PKG_ROOT="$PKG_WORK_DIR/root"
COMPONENT_PKG="$PKG_WORK_DIR/iData-app-component.pkg"
PRODUCT_ID="io.github.leoarrow.idata.installer"
COMPONENT_ID="io.github.leoarrow.idata.pkg.app"
SCRIPTS_DIR="$ROOT_DIR/scripts/pkg"

export COPYFILE_DISABLE=1

if [[ ! -d "$APP_DIR" ]]; then
  echo "missing app bundle: $APP_DIR" >&2
  echo "build the release app first with ./scripts/build_app.sh" >&2
  exit 1
fi

rm -rf "$PKG_WORK_DIR"
mkdir -p "$PKG_ROOT/Applications"

ditto --noextattr --noqtn "$APP_DIR" "$PKG_ROOT/Applications/iData.app"
xattr -cr "$PKG_ROOT/Applications/iData.app"

pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$SCRIPTS_DIR" \
  --identifier "$COMPONENT_ID" \
  --version "$VERSION" \
  --install-location / \
  "$COMPONENT_PKG"

productbuild \
  --package "$COMPONENT_PKG" \
  --identifier "$PRODUCT_ID" \
  --version "$VERSION" \
  "$FINAL_PKG"

if ! pkgutil --check-signature "$FINAL_PKG"; then
  printf 'Package is currently unsigned: %s\n' "$FINAL_PKG" >&2
fi

printf 'Created %s\n' "$FINAL_PKG"
