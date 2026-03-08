#!/bin/zsh
set -euo pipefail

GUIDE_PATH="/Users/Shared/iData/VisiData Setup Guide.md"
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

read '?Press Return to open the Markdown guide in TextEdit...'
/usr/bin/open -a TextEdit "$GUIDE_PATH" || true
read '?Press Return to close this helper...'
