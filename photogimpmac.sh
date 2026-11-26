#!/bin/bash
# PhotoGIMP automated installer for macOS (GIMP 2.10 and 3.x)
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.1.0"
DEFAULT_DOWNLOAD_URL="https://github.com/Diolinux/PhotoGIMP/releases/latest/download/PhotoGIMP.zip"

DRY_RUN=0
DO_DOWNLOAD=0
DO_BACKUP=1
SKIP_RUNNING_CHECK=0
ZIP_FILE=""
DOWNLOAD_URL="$DEFAULT_DOWNLOAD_URL"
DOWNLOADS_DIR="$HOME/Downloads"
GIMP_BIN=""
CONFIG_DIR_OVERRIDE=""
TMP_DIR=""

cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
    cat <<EOF
PhotoGIMP Automated Installer for macOS (v$SCRIPT_VERSION)

Usage:
  $SCRIPT_NAME [OPTIONS]

Options:
  -h, --help                Show this help message and exit
  -V, --version             Show installer version and exit
  -n, --dry-run             Validate environment and print planned actions without modifying files
  -d, --download            Download the latest PhotoGIMP.zip from GitHub using curl
  -z, --zip <path>          Path to a local PhotoGIMP zip archive (overrides Downloads lookup)
      --url <url>           Download URL to use with --download
                            (default: $DEFAULT_DOWNLOAD_URL)
      --downloads-dir <dir> Directory to search for PhotoGIMP*.zip (default: ~/Downloads)
      --gimp-bin <path>     Path to the GIMP executable
      --config-dir <dir>    Target GIMP profile directory (default: ~/Library/Application Support/GIMP/<ver>)
      --no-backup           Skip creating a timestamped backup of the existing GIMP profile
      --skip-running-check  Skip checking whether GIMP is currently running

Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME --dry-run
  $SCRIPT_NAME --download
  $SCRIPT_NAME --zip ~/Downloads/PhotoGIMP.zip
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

require_arg() {
    if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        die "Option '$1' requires a non-empty argument."
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -V|--version)
                echo "$SCRIPT_NAME $SCRIPT_VERSION"
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -d|--download)
                DO_DOWNLOAD=1
                shift
                ;;
            -z|--zip)
                require_arg "$1" "${2:-}"
                ZIP_FILE="$2"
                shift 2
                ;;
            --url)
                require_arg "$1" "${2:-}"
                DOWNLOAD_URL="$2"
                shift 2
                ;;
            --downloads-dir)
                require_arg "$1" "${2:-}"
                DOWNLOADS_DIR="$2"
                shift 2
                ;;
            --gimp-bin)
                require_arg "$1" "${2:-}"
                GIMP_BIN="$2"
                shift 2
                ;;
            --config-dir)
                require_arg "$1" "${2:-}"
                CONFIG_DIR_OVERRIDE="$2"
                shift 2
                ;;
            --no-backup)
                DO_BACKUP=0
                shift
                ;;
            --skip-running-check)
                SKIP_RUNNING_CHECK=1
                shift
                ;;
            *)
                die "Unknown option: '$1'. Run '$SCRIPT_NAME --help' for usage."
                ;;
        esac
    done

    if [ -n "$ZIP_FILE" ] && [ "$DO_DOWNLOAD" -eq 1 ]; then
        die "Options --zip and --download cannot be used together."
    fi
}

detect_gimp_bin() {
    if [ -n "$GIMP_BIN" ]; then
        if [ ! -x "$GIMP_BIN" ]; then
            die "Specified GIMP binary is not executable: $GIMP_BIN"
        fi
        return 0
    fi

    local candidates=(
        "/Applications/GIMP.app/Contents/MacOS/gimp"
        "/Applications/GIMP-3.0.app/Contents/MacOS/gimp"
    )
    local app_root app
    for app_root in "/Applications" "$HOME/Applications"; do
        for app in "$app_root"/GIMP-3.*.app/Contents/MacOS/gimp "$app_root"/GIMP-3.*.app/Contents/MacOS/gimp-3.*; do
            if [ -x "$app" ]; then
                candidates[${#candidates[@]}]="$app"
            fi
        done
    done

    candidates=(
        "${candidates[@]}"
        "$HOME/Applications/GIMP.app/Contents/MacOS/gimp"
        "$HOME/Applications/GIMP-3.0.app/Contents/MacOS/gimp"
        "/Applications/GIMP-2.10.app/Contents/MacOS/gimp"
        "$HOME/Applications/GIMP-2.10.app/Contents/MacOS/gimp"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
        if [ -x "$candidate" ]; then
            GIMP_BIN="$candidate"
            return 0
        fi
    done

    local cmd
    for cmd in gimp gimp-3.0 gimp-2.10; do
        if command -v "$cmd" >/dev/null 2>&1; then
            GIMP_BIN="$(command -v "$cmd")"
            return 0
        fi
    done

    die "GIMP installation was not found. Install GIMP 2.10 or 3.x, or pass --gimp-bin <path>."
}

detect_gimp_version() {
    local version_output
    version_output=$("$GIMP_BIN" --version 2>/dev/null || true)

    GIMP_VERSION=$(printf '%s\n' "$version_output" | awk '
        {
            for (i = 1; i <= NF; i++) {
                if (match($i, /^[0-9]+\.[0-9]+(\.[0-9]+)?/)) {
                    print substr($i, RSTART, RLENGTH)
                    exit
                }
            }
        }
    ')

    if [ -z "$GIMP_VERSION" ]; then
        die "Could not determine GIMP version from '$GIMP_BIN --version'."
    fi

    GIMP_MAJOR="${GIMP_VERSION%%.*}"
    local rest="${GIMP_VERSION#*.}"
    GIMP_MINOR="${rest%%.*}"
    GIMP_MAJOR_MINOR="${GIMP_MAJOR}.${GIMP_MINOR}"

    if [ "$GIMP_MAJOR" -lt 2 ] || { [ "$GIMP_MAJOR" -eq 2 ] && [ "$GIMP_MINOR" -lt 10 ]; }; then
        die "GIMP version '$GIMP_VERSION' is not supported. Requires GIMP 2.10 or 3.x."
    fi
}

check_gimp_not_running() {
    if [ "$SKIP_RUNNING_CHECK" -eq 1 ]; then
        return 0
    fi

    if ! command -v pgrep >/dev/null 2>&1; then
        return 0
    fi

    if pgrep -x "gimp" >/dev/null 2>&1 \
        || pgrep -x "gimp-3.0" >/dev/null 2>&1 \
        || pgrep -x "gimp-2.10" >/dev/null 2>&1 \
        || pgrep -f "GIMP(-[0-9.]+)?\.app/Contents/MacOS/" >/dev/null 2>&1; then
        echo "" >&2
        die "GIMP is currently running. Please quit GIMP (Cmd + Q) and rerun this script."
    fi
}

find_local_zip() {
    if [ -n "$ZIP_FILE" ]; then
        if [ ! -f "$ZIP_FILE" ] || [ ! -r "$ZIP_FILE" ]; then
            die "PhotoGIMP zip archive not found or unreadable: $ZIP_FILE"
        fi
        return 0
    fi

    if [ ! -d "$DOWNLOADS_DIR" ]; then
        return 1
    fi

    local name
    for name in "PhotoGIMP.zip" "photogimp.zip" "PhotoGIMP-master.zip" "PhotoGIMP-main.zip"; do
        if [ -f "$DOWNLOADS_DIR/$name" ] && [ -r "$DOWNLOADS_DIR/$name" ]; then
            ZIP_FILE="$DOWNLOADS_DIR/$name"
            return 0
        fi
    done

    ZIP_FILE=$(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -iname "*photogimp*.zip" 2>/dev/null | LC_ALL=C sort | sed -n '1p')
    if [ -n "$ZIP_FILE" ] && [ -r "$ZIP_FILE" ]; then
        return 0
    fi

    ZIP_FILE=""
    return 1
}

download_zip() {
    command -v curl >/dev/null 2>&1 || die "'curl' is required for --download but was not found."

    ZIP_FILE="$TMP_DIR/PhotoGIMP.zip"
    echo "Downloading PhotoGIMP from: $DOWNLOAD_URL"
    if ! curl -fsSL --connect-timeout 15 --retry 3 -o "$ZIP_FILE" "$DOWNLOAD_URL"; then
        die "Failed to download PhotoGIMP archive from: $DOWNLOAD_URL"
    fi

    if [ ! -s "$ZIP_FILE" ]; then
        die "Downloaded PhotoGIMP archive is empty: $DOWNLOAD_URL"
    fi
}

locate_archive_root() {
    local extract_dir="$1"

    if [ -d "$extract_dir/.config/GIMP" ] || [ -d "$extract_dir/3.0" ] || [ -d "$extract_dir/2.10" ]; then
        printf '%s\n' "$extract_dir"
        return 0
    fi

    local sub
    for sub in "PhotoGIMP-master" "PhotoGIMP-main" "PhotoGIMP"; do
        if [ -d "$extract_dir/$sub" ]; then
            printf '%s\n' "$extract_dir/$sub"
            return 0
        fi
    done

    local first_dir=""
    local dir_count=0
    local entry
    for entry in "$extract_dir"/*; do
        if [ -d "$entry" ]; then
            first_dir="$entry"
            dir_count=$((dir_count + 1))
        fi
    done

    if [ "$dir_count" -eq 1 ] && [ -n "$first_dir" ]; then
        printf '%s\n' "$first_dir"
        return 0
    fi

    printf '%s\n' "$extract_dir"
}

resolve_config_source() {
    local archive_root="$1"
    local candidate

    if [ "$GIMP_MAJOR" -ge 3 ]; then
        for candidate in \
            "$archive_root/.config/GIMP/$GIMP_MAJOR_MINOR" \
            "$archive_root/$GIMP_MAJOR_MINOR" \
            "$archive_root/.config/GIMP/3.0" \
            "$archive_root/3.0"; do
            if [ -d "$candidate" ]; then
                CONFIG_SRC="$candidate"
                return 0
            fi
        done

        if [ -d "$archive_root/.config/GIMP/2.10" ] || [ -d "$archive_root/2.10" ]; then
            die "Archive '$ZIP_FILE' only contains GIMP 2.10 configuration, which is incompatible with GIMP $GIMP_VERSION."
        fi
        die "Could not find GIMP 3.x configuration files inside '$ZIP_FILE'."
    fi

    for candidate in \
        "$archive_root/.config/GIMP/2.10" \
        "$archive_root/2.10"; do
        if [ -d "$candidate" ]; then
            CONFIG_SRC="$candidate"
            return 0
        fi
    done

    if [ -d "$archive_root/.config/GIMP/3.0" ] || [ -d "$archive_root/3.0" ]; then
        die "Archive '$ZIP_FILE' only contains GIMP 3.x configuration, which is incompatible with GIMP $GIMP_VERSION."
    fi
    die "Could not find GIMP 2.10 configuration files inside '$ZIP_FILE'."
}

make_unique_backup_dir() {
    local parent_dir="$1"
    local base_name="GIMP-backup-$(date +%Y%m%d-%H%M%S)"
    local candidate="$parent_dir/$base_name"
    local suffix=1

    while [ -e "$candidate" ]; do
        candidate="$parent_dir/${base_name}-${suffix}"
        suffix=$((suffix + 1))
    done

    printf '%s\n' "$candidate"
}

main() {
    parse_args "$@"

    echo "PhotoGIMP Automated Installer for macOS"
    echo "======================================="

    detect_gimp_bin
    detect_gimp_version

    if [ -n "$CONFIG_DIR_OVERRIDE" ]; then
        GIMP_CONFIG="${CONFIG_DIR_OVERRIDE%/}"
    else
        GIMP_CONFIG="$HOME/Library/Application Support/GIMP/$GIMP_MAJOR_MINOR"
    fi

    echo "Detected GIMP Binary: $GIMP_BIN"
    echo "Detected GIMP Version: $GIMP_VERSION"
    echo "Target Config Directory: $GIMP_CONFIG"

    if [ ! -d "$GIMP_CONFIG" ]; then
        echo "" >&2
        die "Directory '$GIMP_CONFIG' does not exist yet. Open GIMP once to generate your profile, close it, and rerun this script."
    fi

    check_gimp_not_running

    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/photogimp.XXXXXX")"

    if [ "$DO_DOWNLOAD" -eq 1 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "[dry-run] Would download PhotoGIMP archive from: $DOWNLOAD_URL"
            if [ "$DO_BACKUP" -eq 1 ]; then
                local preview_backup
                preview_backup="$(make_unique_backup_dir "$(dirname "$GIMP_CONFIG")")"
                echo "[dry-run] Would back up '$GIMP_CONFIG' to '$preview_backup'"
            fi
            echo "[dry-run] Would extract archive and install PhotoGIMP config into '$GIMP_CONFIG'"
            echo "[dry-run] No files were modified."
            exit 0
        fi
        download_zip
    elif ! find_local_zip; then
        die "Could not find PhotoGIMP.zip in '$DOWNLOADS_DIR'. Place PhotoGIMP.zip there, pass --zip <path>, or pass --download."
    fi

    command -v unzip >/dev/null 2>&1 || die "'unzip' is required but was not found."

    local extract_dir="$TMP_DIR/extracted"
    mkdir -p "$extract_dir"

    echo "Extracting $(basename "$ZIP_FILE")..."
    if ! unzip -q -o "$ZIP_FILE" -d "$extract_dir"; then
        die "Failed to extract PhotoGIMP archive: $ZIP_FILE"
    fi
    rm -rf "$extract_dir/__MACOSX"

    local archive_root
    archive_root="$(locate_archive_root "$extract_dir")"
    CONFIG_SRC=""
    resolve_config_source "$archive_root"

    if [ -z "$(find "$CONFIG_SRC" -mindepth 1 -maxdepth 1 2>/dev/null | sed -n '1p')" ]; then
        die "Resolved PhotoGIMP configuration directory is empty: $CONFIG_SRC"
    fi

    local backup_dir=""
    if [ "$DO_BACKUP" -eq 1 ]; then
        backup_dir="$(make_unique_backup_dir "$(dirname "$GIMP_CONFIG")")"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] Using archive: $ZIP_FILE"
        echo "[dry-run] Source config directory: $CONFIG_SRC"
        if [ "$DO_BACKUP" -eq 1 ]; then
            echo "[dry-run] Would back up '$GIMP_CONFIG' to '$backup_dir'"
        else
            echo "[dry-run] Backup skipped (--no-backup)"
        fi
        echo "[dry-run] Would install PhotoGIMP config into '$GIMP_CONFIG'"
        echo "[dry-run] No files were modified."
        exit 0
    fi

    if [ "$DO_BACKUP" -eq 1 ]; then
        echo "Backing up current config to: $backup_dir"
        mkdir -p "$backup_dir"
        cp -R "$GIMP_CONFIG" "$backup_dir/"
    fi

    echo "Installing PhotoGIMP config..."
    cp -Rf "$CONFIG_SRC/." "$GIMP_CONFIG/"

    echo ""
    echo "Done! Launch GIMP to start using PhotoGIMP."
}

main "$@"
