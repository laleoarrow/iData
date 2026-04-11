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
PYXLSB_STATUS="not detected"
XLRD_STATUS="not detected"
ZSTANDARD_STATUS="not detected"

refresh_detection() {
  PIPX_BIN=$(command -v pipx || true)
  PYTHON3_BIN=$(command -v python3 || true)
  VD_BIN=$(command -v vd || true)
  PIPX_VISIDATA_STATUS="not detected"
  OPENPYXL_STATUS="not detected"
  PYXLSB_STATUS="not detected"
  XLRD_STATUS="not detected"
  ZSTANDARD_STATUS="not detected"

  if [[ -n "$PIPX_BIN" ]]; then
    if "$PIPX_BIN" runpip visidata show visidata >/dev/null 2>&1; then
      PIPX_VISIDATA_STATUS="installed"
    fi

    if "$PIPX_BIN" runpip visidata show openpyxl >/dev/null 2>&1; then
      OPENPYXL_STATUS="installed in the visidata pipx environment"
    else
      OPENPYXL_STATUS="missing from the visidata pipx environment"
    fi

    if "$PIPX_BIN" runpip visidata show pyxlsb >/dev/null 2>&1; then
      PYXLSB_STATUS="installed in the visidata pipx environment"
    else
      PYXLSB_STATUS="missing from the visidata pipx environment"
    fi

    if "$PIPX_BIN" runpip visidata show xlrd >/dev/null 2>&1; then
      XLRD_STATUS="installed in the visidata pipx environment"
    else
      XLRD_STATUS="missing from the visidata pipx environment"
    fi

    if "$PIPX_BIN" runpip visidata show zstandard >/dev/null 2>&1; then
      ZSTANDARD_STATUS="installed in the visidata pipx environment"
    else
      ZSTANDARD_STATUS="missing from the visidata pipx environment"
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
- pyxlsb for Excel Binary Workbook loaders: $PYXLSB_STATUS
- xlrd for legacy Excel loaders: $XLRD_STATUS
- zstandard for compressed inputs: $ZSTANDARD_STATUS

Recommended setup path
----------------------
1. Install pipx
   - preferred on macOS: brew install pipx
   - fallback: python3 -m pip install --user pipx
2. Add pipx apps to PATH
   - pipx ensurepath
3. Install VisiData into pipx
   - pipx install visidata
4. Add common workbook and compression support
   - pipx inject visidata openpyxl pyxlsb xlrd zstandard
5. Verify the environment
   - pipx list
   - pipx runpip visidata show openpyxl pyxlsb xlrd zstandard
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
    if ! brew install visidata && ! brew upgrade visidata; then
      echo "Failed to install or upgrade VisiData with Homebrew."
      return 1
    fi
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
    if ! pipx install visidata && ! pipx upgrade visidata; then
      echo "Failed to install or upgrade VisiData with pipx."
      return 1
    fi
  fi

  if command -v pipx >/dev/null 2>&1; then
    echo "Injecting common workbook and compression packages into the visidata pipx environment..."
    if ! pipx inject visidata openpyxl pyxlsb xlrd zstandard; then
      echo "Failed to inject workbook/compression dependencies into pipx visidata."
      return 1
    fi
  fi

  echo ""
  echo "Verification:"
  if ! command -v vd >/dev/null 2>&1; then
    echo "vd is still missing on PATH after setup."
    return 1
  fi
  command -v vd
  if ! vd --version; then
    echo "vd is present but version check failed."
    return 1
  fi

  return 0
}

refresh_detection
print_status

if [[ "$AUTO_INSTALL" -eq 1 ]]; then
  if install_visidata; then
    setup_status="completed successfully"
  else
    setup_status="failed"
  fi
  refresh_detection
  echo ""
  echo "Setup flow $setup_status."
  if [[ -n "$VD_BIN" ]]; then
    echo "If iData still cannot detect vd, click Auto Detect in Preferences."
  else
    echo "vd is still missing. Resolve the error above, then run this helper again."
  fi
  read '?Press Return to close this helper...'
  if [[ -n "$VD_BIN" ]]; then
    exit 0
  fi
  exit 1
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
    if install_visidata; then
      setup_status="completed successfully"
    else
      setup_status="failed"
    fi
    refresh_detection
    echo ""
    echo "Setup flow $setup_status."
    if [[ -n "$VD_BIN" ]]; then
      echo "If iData still cannot detect vd, click Auto Detect in Preferences."
    else
      echo "vd is still missing. Resolve the error above, then run this helper again."
    fi
    read '?Press Return to close this helper...'
    ;;
  G)
    /usr/bin/open -a TextEdit "$GUIDE_PATH" || true
    read '?Press Return to close this helper...'
    ;;
  *)
    ;;
esac
