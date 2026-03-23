#!/bin/bash
set -eo pipefail

# ---------------------------------------------------------------------------
# obsidian-claude uninstaller
# ---------------------------------------------------------------------------

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}obsidian-claude uninstall${NC}"
echo ""
echo "This will remove all obsidian-claude components from your system."
echo ""
echo -e "${BOLD}Will be removed:${NC}"
echo "  - Obsidian File Watcher (process + login item)"
echo "  - /Applications/Open in Obsidian.app"
echo "  - /Applications/Obsidian File Watcher.app"
echo "  - Claude Code hooks (obsidian-pre-edit.sh, obsidian-post-edit.sh)"
echo "  - Hook entries in ~/.claude/settings.json"
echo "  - File handler overrides (reset to defaults)"
echo ""
echo -e "${BOLD}Will NOT be touched:${NC}"
echo "  - Your Obsidian vault and all files in it"
echo "  - Your Obsidian plugins and settings"
echo "  - Homebrew and duti"
echo "  - Any other Claude Code hooks or settings"
echo ""

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
read -rp "Continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 0
fi

echo ""

# ---------------------------------------------------------------------------
# Phase 1: Stop File Watcher
# ---------------------------------------------------------------------------
echo -e "${BOLD}[1/5] Stopping file watcher...${NC}"

pkill -f "obsidian-file-watcher" 2>/dev/null || true
osascript -e 'tell application "System Events" to delete login item "Obsidian File Watcher"' 2>/dev/null || true

echo -e "${GREEN}  Done.${NC}"

# ---------------------------------------------------------------------------
# Phase 2: Remove apps
# ---------------------------------------------------------------------------
echo -e "${BOLD}[2/5] Removing apps...${NC}"

rm -rf "/Applications/Open in Obsidian.app"
rm -rf "/Applications/Obsidian File Watcher.app"

echo -e "${GREEN}  Done.${NC}"

# ---------------------------------------------------------------------------
# Phase 3: Remove hooks
# ---------------------------------------------------------------------------
echo -e "${BOLD}[3/5] Removing hook scripts...${NC}"

rm -f ~/.claude/hooks/obsidian-post-edit.sh
rm -f ~/.claude/hooks/obsidian-pre-edit.sh

echo -e "${GREEN}  Done.${NC}"

# ---------------------------------------------------------------------------
# Phase 4: Remove hook config from settings.json
# ---------------------------------------------------------------------------
echo -e "${BOLD}[4/5] Cleaning settings.json...${NC}"

SETTINGS_FILE="$HOME/.claude/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
    python3 -c "
import json, sys

path = '$SETTINGS_FILE'

with open(path, 'r') as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
changed = False

for key in ('PreToolUse', 'PostToolUse'):
    entries = hooks.get(key, [])
    if not entries:
        continue
    filtered = []
    for entry in entries:
        cmds = entry.get('command', []) if isinstance(entry, dict) else []
        # Keep this entry unless any command ends with our hook scripts
        if any(
            isinstance(c, str) and (
                c.endswith('obsidian-pre-edit.sh') or
                c.endswith('obsidian-post-edit.sh')
            )
            for c in cmds
        ):
            changed = True
        else:
            filtered.append(entry)
    if filtered:
        hooks[key] = filtered
    else:
        hooks.pop(key, None)
        changed = True

if not hooks:
    settings.pop('hooks', None)
else:
    settings['hooks'] = hooks

if changed:
    with open(path, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print('  Cleaned hook entries from settings.json.')
else:
    print('  No obsidian-claude entries found in settings.json.')
"
else
    echo -e "${YELLOW}  ~/.claude/settings.json not found, skipping.${NC}"
fi

echo -e "${GREEN}  Done.${NC}"

# ---------------------------------------------------------------------------
# Phase 5: Reset file handlers
# ---------------------------------------------------------------------------
echo -e "${BOLD}[5/5] Resetting file handlers...${NC}"

duti -s com.apple.TextEdit public.plain-text all 2>/dev/null || true
duti -s com.apple.TextEdit .txt all 2>/dev/null || true
duti -s md.obsidian net.daringfireball.markdown all 2>/dev/null || true
duti -s md.obsidian .md all 2>/dev/null || true

echo -e "${GREEN}  Done.${NC}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}Uninstall complete.${NC}"
echo ""
echo -e "${GREEN}Removed:${NC}"
echo -e "  ${GREEN}\xE2\x9C\x93${NC} File watcher process and login item"
echo -e "  ${GREEN}\xE2\x9C\x93${NC} /Applications/Open in Obsidian.app"
echo -e "  ${GREEN}\xE2\x9C\x93${NC} /Applications/Obsidian File Watcher.app"
echo -e "  ${GREEN}\xE2\x9C\x93${NC} Hook scripts (obsidian-pre-edit.sh, obsidian-post-edit.sh)"
echo -e "  ${GREEN}\xE2\x9C\x93${NC} Hook config from settings.json"
echo -e "  ${GREEN}\xE2\x9C\x93${NC} File handler overrides (reset to defaults)"
echo ""
echo -e "${BOLD}NOT touched:${NC}"
echo "  - Your Obsidian vault and all files in it"
echo "  - Your Obsidian plugins and settings"
echo "  - Homebrew and duti"
echo "  - Any other Claude Code hooks or settings"
echo ""
