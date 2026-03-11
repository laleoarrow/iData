#!/bin/zsh
set -euo pipefail

AUTO_INSTALL=0
if [[ "${1:-}" == "--install" ]]; then
  AUTO_INSTALL=1
  shift || true
fi

GUIDE_PATH="/Users/Shared/iData/VisiData Setup Guide.md"
PIPX_BIN=""
PYTHON3_BIN=""
VD_BIN=""
PIPX_VISIDATA_STATUS="not detected"
OPENPYXL_STATUS="not detected"

refresh_detection() {
  PIPX_BIN=$(command -v pipx || true)
  PYTHON3_BIN=$(command -v python3 || true)
  VD_BIN=$(command -v vd || true)
  PIPX_VISIDATA_STATUS="not detected"
  OPENPYXL_STATUS="not detected"

  if [[ -n "$PIPX_BIN" ]]; then
    if "$PIPX_BIN" runpip visidata show visidata >/dev/null 2>&1; then
      PIPX_VISIDATA_STATUS="installed"
    fi

    if "$PIPX_BIN" runpip visidata show openpyxl >/dev/null 2>&1; then
      OPENPYXL_STATUS="installed in the visidata pipx environment"
    else
      OPENPYXL_STATUS="missing from the visidata pipx environment"
    fi
  fi
}

print_status() {
  clear
  cat <<EOF
iData post-install helper
=========================

Detected on this Mac:
- python3: ${PYTHON3_BIN:-missing}
- pipx: ${PIPX_BIN:-missing}
- vd on PATH: ${VD_BIN:-missing}
- pipx visidata environment: $PIPX_VISIDATA_STATUS
- openpyxl for Excel loaders: $OPENPYXL_STATUS

Recommended setup path
----------------------
1. Install pipx
   - preferred on macOS: brew install pipx
   - fallback: python3 -m pip install --user pipx
2. Add pipx apps to PATH
   - pipx ensurepath
3. Install VisiData into pipx
   - pipx install visidata
4. Add Excel support for .xlsx/.xlsm loaders
   - pipx inject visidata openpyxl
5. Verify the environment
   - pipx list
   - pipx runpip visidata show openpyxl
   - command -v vd

iData notes
-----------
- iData launches your local vd executable; it does not bundle VisiData.
- If iData cannot find vd automatically, open iData > Preferences and set the executable path manually.
- pipx commonly exposes vd at ~/.local/bin/vd after pipx ensurepath.

Official docs
-------------
- https://pipx.pypa.io/stable/installation/
- https://pipx.pypa.io/stable/docs/
- https://www.visidata.org/install/
- https://www.visidata.org/docs/formats/
- https://openpyxl.readthedocs.io/en/stable/
EOF
}

install_visidata() {
  echo ""
  echo "Starting one-click VisiData setup..."
  echo "------------------------------------"

  if command -v brew >/dev/null 2>&1; then
    echo "Using Homebrew to install/upgrade VisiData..."
    brew install visidata || brew upgrade visidata || true
  else
    if ! command -v pipx >/dev/null 2>&1; then
      if command -v python3 >/dev/null 2>&1; then
        echo "pipx missing, installing with python3 --user..."
        python3 -m pip install --user pipx
        python3 -m pipx ensurepath || true
        export PATH="$HOME/.local/bin:$PATH"
      else
        echo "python3 is missing. Install Homebrew or python3 first, then retry."
        return 1
      fi
    fi

    echo "Using pipx to install/upgrade VisiData..."
    pipx install visidata || pipx upgrade visidata || true
  fi

  if command -v pipx >/dev/null 2>&1; then
    echo "Injecting openpyxl into visidata pipx environment..."
    pipx inject visidata openpyxl || true
  fi

  echo ""
  echo "Verification:"
  command -v vd || true
  vd --version || true
}

refresh_detection
print_status

if [[ "$AUTO_INSTALL" -eq 1 ]]; then
  install_visidata || true
  refresh_detection
  echo ""
  echo "Setup flow completed."
  echo "If vd is still not detected in iData, click Auto Detect in Preferences."
  read '?Press Return to close this helper...'
  exit 0
fi

echo ""
echo "Actions"
echo "-------"
echo "[I] Install/configure now"
echo "[G] Open Markdown guide in TextEdit"
echo "[Q] Quit"
read '?Choose an action (I/G/Q): ' action

case "${action:u}" in
  I)
    install_visidata || true
    refresh_detection
    echo ""
    echo "If vd is still not detected in iData, click Auto Detect in Preferences."
    read '?Press Return to close this helper...'
    ;;
  G)
    /usr/bin/open -a TextEdit "$GUIDE_PATH" || true
    read '?Press Return to close this helper...'
    ;;
  *)
    ;;
esac
