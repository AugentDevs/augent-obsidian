#!/bin/bash
set -eo pipefail

# =============================================================================
# obsidian-claude setup
# Make every .txt and .md file on your Mac open directly in Obsidian.
# =============================================================================

VERSION="2.0.0"
GITHUB_RAW="https://raw.githubusercontent.com/AugentDevs/obsidian-claude/main"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Helpers ---
info()    { echo -e "${BOLD}$1${NC}"; }
success() { echo -e "${GREEN}$1${NC}"; }
warn()    { echo -e "${YELLOW}$1${NC}"; }
error()   { echo -e "${RED}$1${NC}"; }
phase()   { echo ""; info "[$1] $2"; echo "---"; }

cleanup() {
    if [[ -n "${BUILD_DIR:-}" && -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
    fi
    if [[ -n "${DOWNLOAD_DIR:-}" && -d "$DOWNLOAD_DIR" ]]; then
        rm -rf "$DOWNLOAD_DIR"
    fi
}
trap cleanup EXIT

# =============================================================================
# Phase 1: Detect environment
# =============================================================================
phase "1/6" "Detect environment"

echo ""
echo -e "${BOLD}  obsidian-claude setup${NC}  v${VERSION}"
echo -e "  $(date +%Y-%m-%d)"
echo ""

# Username
USERNAME="$USER"
success "  User: $USERNAME"

# Obsidian installed?
if ls /Applications/Obsidian.app > /dev/null 2>&1; then
    success "  Obsidian.app found"
else
    error "  Obsidian.app not found in /Applications"
    error "  Install Obsidian from https://obsidian.md before running this script."
    exit 1
fi

# Auto-detect vaults
echo "  Searching for Obsidian vaults..."
VAULT_DIRS=()
while IFS= read -r line; do
    VAULT_DIRS+=("$(dirname "$line")")
done < <(find ~/Desktop ~/Documents ~/ -maxdepth 3 -name ".obsidian" -type d 2>/dev/null | head -10)

if [[ ${#VAULT_DIRS[@]} -eq 0 ]]; then
    warn "  No vaults found automatically."
    echo -n "  Enter your vault path: "
    read -r VAULT_PATH
    if [[ ! -d "$VAULT_PATH/.obsidian" ]]; then
        error "  $VAULT_PATH does not appear to be an Obsidian vault (no .obsidian directory)."
        exit 1
    fi
elif [[ ${#VAULT_DIRS[@]} -eq 1 ]]; then
    VAULT_PATH="${VAULT_DIRS[0]}"
    success "  Found vault: $VAULT_PATH"
else
    echo "  Found multiple vaults:"
    for i in "${!VAULT_DIRS[@]}"; do
        echo "    $((i+1))) ${VAULT_DIRS[$i]}"
    done
    echo -n "  Select vault [1-${#VAULT_DIRS[@]}]: "
    read -r choice
    if [[ "$choice" -ge 1 && "$choice" -le ${#VAULT_DIRS[@]} ]] 2>/dev/null; then
        VAULT_PATH="${VAULT_DIRS[$((choice-1))]}"
    else
        error "  Invalid selection."
        exit 1
    fi
    success "  Using vault: $VAULT_PATH"
fi

# Strip trailing slash
VAULT_PATH="${VAULT_PATH%/}"

# Xcode CLT
if xcode-select -p > /dev/null 2>&1; then
    success "  Xcode Command Line Tools installed"
else
    warn "  Xcode Command Line Tools not found. Installing..."
    xcode-select --install
    echo "  Waiting for Xcode CLT installation to complete..."
    echo "  Click 'Install' in the dialog that appeared, then wait."
    until xcode-select -p > /dev/null 2>&1; do
        sleep 5
    done
    success "  Xcode Command Line Tools installed"
fi

# python3
if command -v python3 > /dev/null 2>&1; then
    success "  python3 found: $(python3 --version 2>&1)"
else
    error "  python3 not found. Install Python 3 before running this script."
    exit 1
fi

# =============================================================================
# Phase 2: Verify Obsidian plugins
# =============================================================================
phase "2/6" "Verify Obsidian plugins"

OBSIDIAN_DIR="$VAULT_PATH/.obsidian"
PLUGINS_OK=true

# community-plugins.json
COMMUNITY_PLUGINS="$OBSIDIAN_DIR/community-plugins.json"
if [[ -f "$COMMUNITY_PLUGINS" ]]; then
    if python3 -c "
import json, sys
plugins = json.load(open('$COMMUNITY_PLUGINS'))
if 'obsidian-custom-file-extensions-plugin' not in plugins:
    print('Missing: Custom File Extensions')
    sys.exit(1)
" 2>/dev/null; then
        success "  Custom File Extensions plugin installed"
    else
        PLUGINS_OK=false
        error "  Missing required plugin: Custom File Extensions by MeepTech"
        echo "  Install it in Obsidian: Settings > Community plugins > Browse"
    fi

    # Check for Local REST API (recommended, not required)
    if python3 -c "
import json, sys
plugins = json.load(open('$COMMUNITY_PLUGINS'))
if 'obsidian-local-rest-api' not in plugins:
    sys.exit(1)
" 2>/dev/null; then
        success "  Local REST API plugin installed (recommended)"
    else
        warn "  Local REST API not installed (optional, recommended for power users)"
        echo "  Adds REST endpoints for searching, reading, and automating your vault."
        echo "  Install: obsidian://show-plugin?id=obsidian-local-rest-api"
    fi
else
    PLUGINS_OK=false
    error "  community-plugins.json not found."
    echo "  Enable community plugins in Obsidian and install:"
    echo "    - Custom File Extensions Plugin (required)"
fi

# app.json -- showUnsupportedFiles
APP_JSON="$OBSIDIAN_DIR/app.json"
if [[ -f "$APP_JSON" ]]; then
    if python3 -c "
import json, sys
cfg = json.load(open('$APP_JSON'))
if not cfg.get('showUnsupportedFiles', False):
    sys.exit(1)
" 2>/dev/null; then
        success "  Detect all file extensions enabled"
    else
        PLUGINS_OK=false
        error "  'Detect all file extensions' is not enabled."
        echo "  Go to Obsidian Settings > Files & Links > Detect all file extensions"
    fi
else
    PLUGINS_OK=false
    error "  app.json not found. Open Obsidian at least once, then enable 'Detect all file extensions'."
fi

if [[ "$PLUGINS_OK" != "true" ]]; then
    echo ""
    error "Fix the issues above and re-run this script."
    exit 1
fi

# =============================================================================
# Phase 3: Install prerequisites
# =============================================================================
phase "3/6" "Install prerequisites"

if command -v brew > /dev/null 2>&1; then
    success "  Homebrew found"
else
    error "  Homebrew not found."
    echo "  Install it: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

if command -v duti > /dev/null 2>&1; then
    success "  duti found"
else
    warn "  duti not found, installing..."
    brew install duti
    success "  duti installed"
fi

# =============================================================================
# Phase 4: Build apps
# =============================================================================
phase "4/6" "Build apps"

BUILD_DIR=$(mktemp -d)

# Determine source: local repo or download from GitHub
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/src/OpenInObsidian.swift" ]]; then
    SRC_DIR="$SCRIPT_DIR/src"
    success "  Using local source files"
else
    warn "  Local source not found, downloading from GitHub..."
    DOWNLOAD_DIR=$(mktemp -d)
    SRC_DIR="$DOWNLOAD_DIR/src"
    mkdir -p "$SRC_DIR"

    FILES=(
        "src/OpenInObsidian.swift"
        "src/ObsidianFileWatcher.swift"
        "src/open-in-obsidian.plist"
        "src/file-watcher.plist"
    )

    for f in "${FILES[@]}"; do
        dest="$DOWNLOAD_DIR/$f"
        echo "  Downloading $f..."
        if ! curl -sfL "$GITHUB_RAW/$f" -o "$dest"; then
            error "  Failed to download $f from GitHub."
            exit 1
        fi
    done
    success "  All source files downloaded"
fi

# Build OpenInObsidian
echo "  Compiling Open in Obsidian..."
sed "s|VAULT_PATH_HERE|$VAULT_PATH|g" "$SRC_DIR/OpenInObsidian.swift" > "$BUILD_DIR/OpenInObsidian.swift"
if ! swiftc -O -o "$BUILD_DIR/open-in-obsidian" "$BUILD_DIR/OpenInObsidian.swift" -framework Cocoa 2>&1; then
    error "  swiftc failed for OpenInObsidian.swift"
    echo "  Try: sudo xcode-select --reset"
    exit 1
fi
success "  open-in-obsidian compiled"

# Build ObsidianFileWatcher
echo "  Compiling Obsidian File Watcher..."
sed "s|VAULT_PATH_HERE|$VAULT_PATH|g" "$SRC_DIR/ObsidianFileWatcher.swift" > "$BUILD_DIR/ObsidianFileWatcher.swift"
if ! swiftc -O -o "$BUILD_DIR/obsidian-file-watcher" "$BUILD_DIR/ObsidianFileWatcher.swift" -framework Cocoa 2>&1; then
    error "  swiftc failed for ObsidianFileWatcher.swift"
    echo "  Try: sudo xcode-select --reset"
    exit 1
fi
success "  obsidian-file-watcher compiled"

# =============================================================================
# Phase 5: Install apps and register file handlers
# =============================================================================
phase "5/6" "Install apps and register file handlers"

# --- Open in Obsidian ---
HANDLER_APP="/Applications/Open in Obsidian.app"
rm -rf "$HANDLER_APP"
mkdir -p "$HANDLER_APP/Contents/MacOS"
cp "$BUILD_DIR/open-in-obsidian" "$HANDLER_APP/Contents/MacOS/open-in-obsidian"
cp "$SRC_DIR/open-in-obsidian.plist" "$HANDLER_APP/Contents/Info.plist"
codesign --force --deep --sign - "$HANDLER_APP"
xattr -cr "$HANDLER_APP"
success "  Open in Obsidian.app installed"

# Register with Launch Services
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister "$HANDLER_APP"

# --- Obsidian File Watcher ---
WATCHER_APP="/Applications/Obsidian File Watcher.app"
rm -rf "$WATCHER_APP"
mkdir -p "$WATCHER_APP/Contents/MacOS"
cp "$BUILD_DIR/obsidian-file-watcher" "$WATCHER_APP/Contents/MacOS/obsidian-file-watcher"
cp "$SRC_DIR/file-watcher.plist" "$WATCHER_APP/Contents/Info.plist"
codesign --force --deep --sign - "$WATCHER_APP"
xattr -cr "$WATCHER_APP"
success "  Obsidian File Watcher.app installed"

# --- Register file handlers ---
BUNDLE_ID="com.local.open-in-obsidian"
duti -s "$BUNDLE_ID" public.plain-text all
duti -s "$BUNDLE_ID" .txt all
duti -s "$BUNDLE_ID" com.apple.traditional-mac-plain-text all
duti -s "$BUNDLE_ID" net.daringfireball.markdown all
duti -s "$BUNDLE_ID" .md all
success "  File handlers registered for .txt and .md"

# =============================================================================
# Phase 6: Verify installation
# =============================================================================
phase "6/6" "Verify installation"

ERRORS=0

# Check apps exist
if [[ -d "/Applications/Open in Obsidian.app" ]]; then
    success "  [ok] Open in Obsidian.app"
else
    error "  [!!] Open in Obsidian.app missing"
    ERRORS=$((ERRORS+1))
fi

if [[ -d "/Applications/Obsidian File Watcher.app" ]]; then
    success "  [ok] Obsidian File Watcher.app"
else
    error "  [!!] Obsidian File Watcher.app missing"
    ERRORS=$((ERRORS+1))
fi

# Check duti registrations
TXT_HANDLER=$(duti -x txt 2>/dev/null | head -1)
if [[ "$TXT_HANDLER" == *"Open in Obsidian"* ]]; then
    success "  [ok] .txt handler: $TXT_HANDLER"
else
    warn "  [--] .txt handler: $TXT_HANDLER (may need logout/login)"
fi

MD_HANDLER=$(duti -x md 2>/dev/null | head -1)
if [[ "$MD_HANDLER" == *"Open in Obsidian"* ]]; then
    success "  [ok] .md handler: $MD_HANDLER"
else
    warn "  [--] .md handler: $MD_HANDLER (may need logout/login)"
fi

# Remove old login item approach (unreliable)
osascript -e 'tell application "System Events" to delete login item "Obsidian File Watcher"' 2>/dev/null || true

# Install launchd agent (auto-starts on login, auto-restarts on crash)
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/com.local.obsidian-file-watcher.plist"
mkdir -p "$PLIST_DIR"

cat > "$PLIST_PATH" << LAUNCHD_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.obsidian-file-watcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Obsidian File Watcher.app/Contents/MacOS/obsidian-file-watcher</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/obsidian-file-watcher.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/obsidian-file-watcher.log</string>
</dict>
</plist>
LAUNCHD_EOF

# Stop any running instance, then load the agent
launchctl unload "$PLIST_PATH" 2>/dev/null || true
pkill -f "obsidian-file-watcher" 2>/dev/null || true
sleep 1
launchctl load "$PLIST_PATH"
success "  [ok] File Watcher installed as LaunchAgent (auto-starts, auto-restarts)"

# --- Summary ---
echo ""
echo "==========================================="
if [[ $ERRORS -eq 0 ]]; then
    success "  obsidian-claude installed successfully!"
else
    warn "  Installation completed with $ERRORS error(s)."
fi
echo "==========================================="
echo ""
echo "  Vault:   $VAULT_PATH"
echo "  Apps:    /Applications/Open in Obsidian.app"
echo "           /Applications/Obsidian File Watcher.app"
echo ""
warn "  Grant Full Disk Access to both apps if prompted:"
warn "  System Settings > Privacy & Security > Full Disk Access"
warn "  Add: Open in Obsidian.app and Obsidian File Watcher.app"
echo ""
if [[ $ERRORS -eq 0 ]]; then
    success "  Done. Double-click any .txt or .md file to open it in Obsidian."
fi
