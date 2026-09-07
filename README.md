# TDC Valheim Modpack

Central configuration and installer for the TDC Valheim server.

## Player installation

Players should only need the two files in `installer/`:

- `TDC-Valheim-Installer.bat`
- `TDC-Valheim-Installer.ps1`

Double-click the BAT file. It launches the PowerShell updater.

## How updates work

`manifest.json` on the `main` branch is the authoritative pack manifest.

Each managed file has:

- `name`
- `version`
- `url`
- `destination`
- `sha256`

The installer downloads the exact URL, verifies its SHA-256 hash, and only
then installs it.

**Do not point entries at an unpinned "latest" asset.** Approve and pin exact
versions before changing `main`.

## Example manifest entry

```json
{
  "name": "ExampleMod.dll",
  "version": "1.2.3",
  "url": "https://example.invalid/ExampleMod.dll",
  "destination": "BepInEx\\plugins\\ExampleMod.dll",
  "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}
```

## Adding configs

Configs can be stored in this repository under `configs/`, then referenced
using the raw GitHub URL in `manifest.json`. Their hashes should be pinned
the same way as mod DLLs.

## Release workflow

1. Update/test mods locally.
2. Update configs.
3. Calculate SHA-256 hashes.
4. Update `manifest.json`.
5. Test the installer against a clean/test Valheim install.
6. Commit to `main` only when the pack is approved.
7. Increment `packVersion`.

## Safety

The installer:
- backs up the existing BepInEx installation before changes;
- only removes files recorded in the previous installed TDC manifest;
- leaves unrelated client mods alone;
- verifies managed files with SHA-256.
