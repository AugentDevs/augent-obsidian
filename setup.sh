#!/bin/bash
set -eo pipefail

# =============================================================================
# augent-obsidian setup
# Make every .txt and .md file on your Mac open directly in Obsidian.
# curl -fsSL https://augent.app/obsidian.sh | bash
# =============================================================================

VERSION="2.0.0"
GITHUB_RAW="https://raw.githubusercontent.com/AugentDevs/augent-obsidian/main"

# --- Colors & Formatting ---
setup_colors() {
    if [[ -t 1 ]] || [[ -r /dev/tty ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;96m'
        BOLD='\033[1m'
        DIM='\033[2m'
        NC='\033[0m'
    else
        RED='' GREEN='' YELLOW='' BLUE='' BOLD='' DIM='' NC=''
    fi
}
setup_colors

# --- Logging ---
log_success() { sleep 0.06; echo -e "  ${GREEN}✓${NC} $*"; }
log_warn()    { echo -e "  ${YELLOW}⚠${NC} $*"; }
log_error()   { echo -e "  ${RED}✗${NC} $*" >&2; }
log_phase()   { sleep 0.3; echo -e "\n\033[38;2;0;240;96m${BOLD}[$1/$2]${NC} ${BOLD}$3${NC}\n"; sleep 0.15; }

# --- Spinner ---
SPINNER_PID=""
start_spinner() {
    local msg=$1
    if [[ -r /dev/tty && -w /dev/tty ]]; then
        (
            local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
            local i=0
            while true; do
                printf "\r  ${BLUE}%s${NC} %s" "${frames[$i]}" "$msg" > /dev/tty
                i=$(( (i + 1) % 10 ))
                sleep 0.08
            done
        ) </dev/null > /dev/null 2>&1 &
        SPINNER_PID=$!
        disown "$SPINNER_PID" 2>/dev/null || true
    else
        echo -e "  ${BLUE}::${NC} $msg"
    fi
}

stop_spinner() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        sleep 0.15
        printf "\r\033[K" > /dev/tty 2>/dev/null || true
        SPINNER_PID=""
    fi
}

# --- Cleanup ---
cleanup() {
    stop_spinner
    if [[ -n "${BUILD_DIR:-}" && -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
    fi
    if [[ -n "${DOWNLOAD_DIR:-}" && -d "$DOWNLOAD_DIR" ]]; then
        rm -rf "$DOWNLOAD_DIR"
    fi
}
trap cleanup EXIT

TOTAL_PHASES=6

# =============================================================================
# Phase 1: Detect environment
# =============================================================================
log_phase 1 $TOTAL_PHASES "Detect environment"

echo -e "  ${BOLD}augent-obsidian${NC} v${VERSION}"
echo -e "  ${DIM}$(date +%Y-%m-%d)${NC}"
echo ""

# Username
log_success "User: $USER"

# Obsidian installed?
if ls /Applications/Obsidian.app > /dev/null 2>&1; then
    log_success "Obsidian.app found"
else
    log_error "Obsidian.app not found in /Applications"
    log_error "Install Obsidian from https://obsidian.md before running this script."
    exit 1
fi

# Auto-detect vaults
start_spinner "Searching for Obsidian vaults"
VAULT_DIRS=()
while IFS= read -r line; do
    VAULT_DIRS+=("$(dirname "$line")")
done < <(find ~/Desktop ~/Documents ~/ -maxdepth 3 -name ".obsidian" -type d 2>/dev/null | head -10)
stop_spinner

if [[ ${#VAULT_DIRS[@]} -eq 0 ]]; then
    log_warn "No vaults found automatically."
    echo -n "  Enter your vault path: "
    read -r VAULT_PATH < /dev/tty
    if [[ ! -d "$VAULT_PATH/.obsidian" ]]; then
        log_error "$VAULT_PATH does not appear to be an Obsidian vault (no .obsidian directory)."
        exit 1
    fi
elif [[ ${#VAULT_DIRS[@]} -eq 1 ]]; then
    VAULT_PATH="${VAULT_DIRS[0]}"
    log_success "Found vault: $VAULT_PATH"
else
    echo "  Found multiple vaults:"
    for i in "${!VAULT_DIRS[@]}"; do
        echo "    $((i+1))) ${VAULT_DIRS[$i]}"
    done
    echo -n "  Select vault [1-${#VAULT_DIRS[@]}]: "
    read -r choice < /dev/tty
    if [[ "$choice" -ge 1 && "$choice" -le ${#VAULT_DIRS[@]} ]] 2>/dev/null; then
        VAULT_PATH="${VAULT_DIRS[$((choice-1))]}"
    else
        log_error "Invalid selection."
        exit 1
    fi
    log_success "Using vault: $VAULT_PATH"
fi

# Strip trailing slash
VAULT_PATH="${VAULT_PATH%/}"

# Xcode CLT
if xcode-select -p > /dev/null 2>&1; then
    log_success "Xcode Command Line Tools installed"
else
    log_warn "Xcode Command Line Tools not found. Installing..."
    xcode-select --install
    echo "  Click 'Install' in the dialog that appeared, then wait."
    until xcode-select -p > /dev/null 2>&1; do
        sleep 5
    done
    log_success "Xcode Command Line Tools installed"
fi

# python3
if command -v python3 > /dev/null 2>&1; then
    log_success "python3 found: $(python3 --version 2>&1)"
else
    log_error "python3 not found. Install Python 3 before running this script."
    exit 1
fi

# =============================================================================
# Phase 2: Verify Obsidian plugins
# =============================================================================
log_phase 2 $TOTAL_PHASES "Verify Obsidian plugins"

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
        log_success "Custom File Extensions plugin installed"
    else
        PLUGINS_OK=false
        log_error "Missing required plugin: Custom File Extensions by MeepTech"
        echo "  Install it in Obsidian: Settings > Community plugins > Browse"
    fi

    # Check for Local REST API (recommended, not required)
    if python3 -c "
import json, sys
plugins = json.load(open('$COMMUNITY_PLUGINS'))
if 'obsidian-local-rest-api' not in plugins:
    sys.exit(1)
" 2>/dev/null; then
        log_success "Local REST API plugin installed (recommended)"
    else
        log_warn "Local REST API not installed (optional, recommended for power users)"
        echo "    Adds REST endpoints for searching, reading, and automating your vault."
    fi
else
    PLUGINS_OK=false
    log_error "community-plugins.json not found."
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
        log_success "Detect all file extensions enabled"
    else
        PLUGINS_OK=false
        log_error "'Detect all file extensions' is not enabled."
        echo "  Go to Obsidian Settings > Files & Links > Detect all file extensions"
    fi
else
    PLUGINS_OK=false
    log_error "app.json not found. Open Obsidian at least once, then enable 'Detect all file extensions'."
fi

if [[ "$PLUGINS_OK" != "true" ]]; then
    echo ""
    log_error "Fix the issues above and re-run this script."
    exit 1
fi

# =============================================================================
# Phase 3: Install prerequisites
# =============================================================================
log_phase 3 $TOTAL_PHASES "Install prerequisites"

if command -v brew > /dev/null 2>&1; then
    log_success "Homebrew found"
else
    log_error "Homebrew not found."
    echo "  Install it: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

if command -v duti > /dev/null 2>&1; then
    log_success "duti found"
else
    start_spinner "Installing duti"
    brew install duti > /dev/null 2>&1
    stop_spinner
    log_success "duti installed"
fi

# =============================================================================
# Phase 4: Build apps
# =============================================================================
log_phase 4 $TOTAL_PHASES "Build apps"

BUILD_DIR=$(mktemp -d)

# Determine source: local repo or download from GitHub
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/src/OpenInObsidian.swift" ]]; then
    SRC_DIR="$SCRIPT_DIR/src"
    log_success "Using local source files"
else
    start_spinner "Downloading source from GitHub"
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
        if ! curl -sfL "$GITHUB_RAW/$f" -o "$dest"; then
            stop_spinner
            log_error "Failed to download $f from GitHub."
            exit 1
        fi
    done
    stop_spinner
    log_success "All source files downloaded"
fi

# Build OpenInObsidian
start_spinner "Compiling Open in Obsidian"
sed "s|VAULT_PATH_HERE|$VAULT_PATH|g" "$SRC_DIR/OpenInObsidian.swift" > "$BUILD_DIR/OpenInObsidian.swift"
if ! swiftc -O -o "$BUILD_DIR/open-in-obsidian" "$BUILD_DIR/OpenInObsidian.swift" -framework Cocoa > /dev/null 2>&1; then
    stop_spinner
    log_error "swiftc failed for OpenInObsidian.swift"
    echo "  Try: sudo xcode-select --reset"
    exit 1
fi
stop_spinner
log_success "Open in Obsidian compiled"

# Build ObsidianFileWatcher
start_spinner "Compiling Obsidian File Watcher"
sed "s|VAULT_PATH_HERE|$VAULT_PATH|g" "$SRC_DIR/ObsidianFileWatcher.swift" > "$BUILD_DIR/ObsidianFileWatcher.swift"
if ! swiftc -O -o "$BUILD_DIR/obsidian-file-watcher" "$BUILD_DIR/ObsidianFileWatcher.swift" -framework Cocoa > /dev/null 2>&1; then
    stop_spinner
    log_error "swiftc failed for ObsidianFileWatcher.swift"
    echo "  Try: sudo xcode-select --reset"
    exit 1
fi
stop_spinner
log_success "Obsidian File Watcher compiled"

# =============================================================================
# Phase 5: Install apps and register file handlers
# =============================================================================
log_phase 5 $TOTAL_PHASES "Install apps and register file handlers"

# --- Open in Obsidian ---
HANDLER_APP="/Applications/Open in Obsidian.app"
rm -rf "$HANDLER_APP"
mkdir -p "$HANDLER_APP/Contents/MacOS"
cp "$BUILD_DIR/open-in-obsidian" "$HANDLER_APP/Contents/MacOS/open-in-obsidian"
cp "$SRC_DIR/open-in-obsidian.plist" "$HANDLER_APP/Contents/Info.plist"
codesign --force --deep --sign - "$HANDLER_APP" > /dev/null 2>&1
xattr -cr "$HANDLER_APP"
log_success "Open in Obsidian.app installed"

# Register with Launch Services
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister "$HANDLER_APP"

# --- Obsidian File Watcher ---
WATCHER_APP="/Applications/Obsidian File Watcher.app"
rm -rf "$WATCHER_APP"
mkdir -p "$WATCHER_APP/Contents/MacOS"
cp "$BUILD_DIR/obsidian-file-watcher" "$WATCHER_APP/Contents/MacOS/obsidian-file-watcher"
cp "$SRC_DIR/file-watcher.plist" "$WATCHER_APP/Contents/Info.plist"
codesign --force --deep --sign - "$WATCHER_APP" > /dev/null 2>&1
xattr -cr "$WATCHER_APP"
log_success "Obsidian File Watcher.app installed"

# --- Register file handlers ---
BUNDLE_ID="com.local.open-in-obsidian"
duti -s "$BUNDLE_ID" public.plain-text all
duti -s "$BUNDLE_ID" .txt all
duti -s "$BUNDLE_ID" com.apple.traditional-mac-plain-text all
duti -s "$BUNDLE_ID" net.daringfireball.markdown all
duti -s "$BUNDLE_ID" .md all
log_success "File handlers registered for .txt and .md"

# =============================================================================
# Phase 6: Verify installation
# =============================================================================
log_phase 6 $TOTAL_PHASES "Verify installation"

ERRORS=0

# Check apps exist
if [[ -d "/Applications/Open in Obsidian.app" ]]; then
    log_success "Open in Obsidian.app"
else
    log_error "Open in Obsidian.app missing"
    ERRORS=$((ERRORS+1))
fi

if [[ -d "/Applications/Obsidian File Watcher.app" ]]; then
    log_success "Obsidian File Watcher.app"
else
    log_error "Obsidian File Watcher.app missing"
    ERRORS=$((ERRORS+1))
fi

# Check duti registrations
TXT_HANDLER=$(duti -x txt 2>/dev/null | head -1)
if [[ "$TXT_HANDLER" == *"Open in Obsidian"* ]]; then
    log_success ".txt handler: $TXT_HANDLER"
else
    log_warn ".txt handler: $TXT_HANDLER (may need logout/login)"
fi

MD_HANDLER=$(duti -x md 2>/dev/null | head -1)
if [[ "$MD_HANDLER" == *"Open in Obsidian"* ]]; then
    log_success ".md handler: $MD_HANDLER"
else
    log_warn ".md handler: $MD_HANDLER (may need logout/login)"
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
log_success "File Watcher installed as LaunchAgent (auto-starts, auto-restarts)"

# --- Summary ---
echo ""
echo -e "  ${GREEN}${BOLD}==========================================${NC}"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}  augent-obsidian installed successfully!${NC}"
else
    echo -e "  ${YELLOW}${BOLD}  Installed with $ERRORS error(s).${NC}"
fi
echo -e "  ${GREEN}${BOLD}==========================================${NC}"
echo ""
echo -e "  ${DIM}Vault:${NC}   $VAULT_PATH"
echo -e "  ${DIM}Apps:${NC}    /Applications/Open in Obsidian.app"
echo -e "           /Applications/Obsidian File Watcher.app"
echo ""
log_warn "Grant Full Disk Access to both apps if prompted:"
echo -e "    System Settings > Privacy & Security > Full Disk Access"
echo -e "    Add: Open in Obsidian.app and Obsidian File Watcher.app"
echo ""
if [[ $ERRORS -eq 0 ]]; then
    log_success "Done. Double-click any .txt or .md file to open it in Obsidian."
fi
