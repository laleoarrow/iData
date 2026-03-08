# iData post-install: configure VisiData with pipx

`iData.app` installs into `/Applications`, but it still expects a local `vd` executable. The recommended first-pass setup is a user-level `pipx` install of VisiData.

## 1. Install pipx

Official pipx docs recommend this on macOS:

```bash
brew install pipx
pipx ensurepath
```

If Homebrew is not available, pipx also documents a Python-based fallback:

```bash
python3 -m pip install --user pipx
python3 -m pipx ensurepath
```

After `ensurepath`, open a new Terminal window before checking:

```bash
command -v pipx
```

## 2. Install VisiData inside pipx

VisiData documents `pipx install visidata` as a supported install path:

```bash
pipx install visidata
```

Check that `vd` resolves on your shell `PATH`:

```bash
command -v vd
vd --version
```

`pipx` commonly exposes apps in `~/.local/bin` on macOS, so `pipx ensurepath` is the important step that makes `vd` discoverable by `iData`.

## 3. Add Excel support with `openpyxl`

The VisiData format reference lists `openpyxl` as the dependency for Excel `.xlsx` loaders. Keep VisiData isolated and add the dependency into the existing `pipx` environment:

```bash
pipx inject visidata openpyxl
```

Verify the Excel dependency:

```bash
pipx runpip visidata show openpyxl
```

## 4. Point iData at `vd` if auto-discovery misses it

If `iData` launches but reports that `vd` is missing:

1. Open `iData`
2. Go to `Preferences`
3. Set the VisiData executable path manually

Typical `pipx` location:

```text
~/.local/bin/vd
```

## 5. Handy verification checklist

```bash
command -v pipx
command -v vd
pipx list
pipx runpip visidata show openpyxl
```

## Official references

- pipx installation: https://pipx.pypa.io/stable/installation/
- pipx command reference: https://pipx.pypa.io/stable/docs/
- VisiData install guide: https://www.visidata.org/install/
- VisiData supported formats: https://www.visidata.org/docs/formats/
- openpyxl docs: https://openpyxl.readthedocs.io/en/stable/
