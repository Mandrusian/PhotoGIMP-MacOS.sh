#!/bin/bash
# PhotoGIMP automated installer for macOS (GIMP 3.x)
set -eu

function version { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

echo "PhotoGIMP Automated Installer for macOS"
echo "======================================="

# Navigate to Downloads directory
cd "$HOME/Downloads"

# Locate and extract PhotoGIMP zip file
ZIP_FILE=""
if [ -f "PhotoGIMP.zip" ]; then
    ZIP_FILE="PhotoGIMP.zip"
elif [ -f "photogimp.zip" ]; then
    ZIP_FILE="photogimp.zip"
elif [ -f "PhotoGIMP-master.zip" ]; then
    ZIP_FILE="PhotoGIMP-master.zip"
else
    # Search for any zip file containing 'PhotoGIMP' (case-insensitive)
    ZIP_FILE=$(find . -maxdepth 1 -iname "*photogimp*.zip" | head -n 1 | sed 's|^\./||')
fi

if [ -z "$ZIP_FILE" ]; then
    echo "Error: Could not find PhotoGIMP.zip in $HOME/Downloads."
    echo "Please place PhotoGIMP.zip in your Downloads folder and try again."
    exit 1
fi

echo "Extracting $ZIP_FILE..."
unzip -q -o "$ZIP_FILE" -d "/tmp/PhotoGIMP_extracted"

# Locate the extracted content folder
EXTRACTED_DIR=""
if [ -d "/tmp/PhotoGIMP_extracted/PhotoGIMP-master" ]; then
    EXTRACTED_DIR="/tmp/PhotoGIMP_extracted/PhotoGIMP-master"
elif [ -d "/tmp/PhotoGIMP_extracted/PhotoGIMP" ]; then
    EXTRACTED_DIR="/tmp/PhotoGIMP_extracted/PhotoGIMP"
else
    EXTRACTED_DIR="/tmp/PhotoGIMP_extracted"
fi

cd "$EXTRACTED_DIR"
echo "Working inside: $(pwd)"

# Detect GIMP installation and version
if [ -x "/Applications/GIMP.app/Contents/MacOS/gimp" ]; then
    GIMP_BIN="/Applications/GIMP.app/Contents/MacOS/gimp"
elif [ -x "/Applications/GIMP-3.0.app/Contents/MacOS/gimp" ]; then
    GIMP_BIN="/Applications/GIMP-3.0.app/Contents/MacOS/gimp"
elif command -v gimp >/dev/null 2>&1; then
    GIMP_BIN="$(command -v gimp)"
else
    echo "Error: GIMP installation was not found."
    exit 1
fi

GIMP_VERSION=$("$GIMP_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)

if [ -z "$GIMP_VERSION" ] || [ "$(version "$GIMP_VERSION")" -lt "$(version "3.0")" ]; then
    echo "Error: GIMP version ($GIMP_VERSION) is below 3.0 or unreadable."
    exit 1
fi

# Determine target profile directory based on GIMP version (e.g., 3.0, 3.2)
MAJOR_MINOR=$(echo "$GIMP_VERSION" | grep -oE '^[0-9]+\.[0-9]+')
GIMP_CONFIG="$HOME/Library/Application Support/GIMP/$MAJOR_MINOR"

echo "Detected GIMP Version: $GIMP_VERSION"
echo "Target Config Directory: $GIMP_CONFIG"

# Locate source configuration files inside extracted archive
if [ -d ".config/GIMP/$MAJOR_MINOR" ]; then
    CONFIG_SRC=".config/GIMP/$MAJOR_MINOR"
elif [ -d ".config/GIMP/3.0" ]; then
    CONFIG_SRC=".config/GIMP/3.0"
elif [ -d "3.0" ]; then
    CONFIG_SRC="3.0"
elif [ -d ".config/GIMP/2.10" ]; then
    CONFIG_SRC=".config/GIMP/2.10"
else
    CONFIG_SRC="."
fi

if [ ! -d "$GIMP_CONFIG" ]; then
    echo ""
    echo "Directory '$GIMP_CONFIG' does not exist yet."
    echo "Please open GIMP once to generate your profile, close it, and rerun this script."
    rm -rf /tmp/PhotoGIMP_extracted
    exit 1
fi

# Ensure GIMP is closed
if pgrep -f "GIMP" >/dev/null 2>&1; then
    echo ""
    echo "GIMP is currently running. Please quit GIMP (Cmd + Q) and rerun this script."
    rm -rf /tmp/PhotoGIMP_extracted
    exit 1
fi

# Create timestamped backup of existing config
BACKUP="$(dirname "$GIMP_CONFIG")/GIMP-backup-$(date +%Y%m%d-%H%M%S)"
echo "Backing up current config to: $BACKUP"
mkdir -p "$BACKUP"
cp -R "$GIMP_CONFIG" "$BACKUP/"

# Install PhotoGIMP files
echo "Installing PhotoGIMP config..."
cp -R "$CONFIG_SRC/." "$GIMP_CONFIG/"

# Cleanup extracted temp files
rm -rf /tmp/PhotoGIMP_extracted

echo ""
echo "Done! Launch GIMP to start using PhotoGIMP."
