# PhotoGIMP macOS Installer

An automated Bash installer to configure [Diolinux PhotoGIMP](https://github.com/Diolinux/PhotoGIMP) on macOS for **GIMP 3.x** (and **GIMP 2.10** when paired with a 2.10 PhotoGIMP archive).

## Prerequisites

1. **macOS** with [GIMP](https://www.gimp.org/downloads/) installed (3.x or 2.10).
2. **Launch GIMP at least once and quit it** (`Cmd + Q`) before running the installer so GIMP generates its default profile directory under `~/Library/Application Support/GIMP/`.
3. Either:
   - Run the installer with `--download` to fetch `PhotoGIMP.zip` automatically via `curl`, **or**
   - Manually download the [PhotoGIMP release archive](https://github.com/Diolinux/PhotoGIMP/releases/latest) into `~/Downloads`.

## Quick Start

1. Clone this repository (or download `photogimpmac.sh`):
   ```bash
   git clone https://github.com/Mandrusian/PhotoGIMP-MacOS.sh.git
   cd PhotoGIMP-MacOS.sh
   chmod +x photogimpmac.sh
   ```

2. Preview what the installer will do without changing any files:
   ```bash
   ./photogimpmac.sh --dry-run
   ```

3. Install PhotoGIMP:
   - Using an archive already in `~/Downloads`:
     ```bash
     ./photogimpmac.sh
     ```
   - Or downloading the latest release automatically:
     ```bash
     ./photogimpmac.sh --download
     ```
   - Or specifying a custom archive path:
     ```bash
     ./photogimpmac.sh --zip /path/to/PhotoGIMP.zip
     ```

## Options

| Flag | Description |
| --- | --- |
| `-h`, `--help` | Show usage information and exit |
| `-V`, `--version` | Show installer version and exit |
| `-n`, `--dry-run` | Validate GIMP, archive, and profile directory without modifying files |
| `-d`, `--download` | Download the latest `PhotoGIMP.zip` from GitHub using `curl` |
| `-z`, `--zip <path>` | Path to a local PhotoGIMP `.zip` archive |
| `--url <url>` | Custom download URL for `--download` |
| `--downloads-dir <dir>` | Directory to search for `PhotoGIMP*.zip` (default: `~/Downloads`) |
| `--gimp-bin <path>` | Override path to the GIMP executable |
| `--config-dir <dir>` | Override target GIMP profile directory |
| `--no-backup` | Skip creating a timestamped backup before installing |
| `--skip-running-check` | Skip checking whether GIMP is currently running |

## What the Installer Does

1. Detects your installed GIMP binary (`/Applications/GIMP.app`, `/Applications/GIMP-3.0.app`, `/Applications/GIMP-2.10.app`, `~/Applications/...`, or `PATH`) and reads its version.
2. Verifies your GIMP profile directory exists (e.g., `~/Library/Application Support/GIMP/3.0` or `2.10`) and that GIMP is not currently running.
3. Locates `PhotoGIMP*.zip` in `~/Downloads` (or downloads it when `--download` is passed), extracts it into a secure temporary directory (`mktemp -d`), and verifies the archive matches your GIMP major version.
4. Creates a timestamped backup of your existing profile at `~/Library/Application Support/GIMP/GIMP-backup-YYYYMMDD-HHMMSS/`.
5. Copies PhotoGIMP configuration files (including dotfiles) into your GIMP profile directory and cleans up temporary files on exit.

## Restoring a Backup

If you ever want to revert to your previous GIMP configuration:

1. Quit GIMP (`Cmd + Q`).
2. Open `~/Library/Application Support/GIMP/` in Finder (`Cmd + Shift + G`).
3. Replace your version folder (for example, `3.0`) with the folder inside the `GIMP-backup-*` directory.

## Running Tests

The repository includes an isolated smoke/integration test suite that uses temporary directories and mocked `gimp`/`curl`/`pgrep` executables so your real GIMP configuration is never touched:

```bash
./tests/test_photogimpmac.sh
```
