#!/bin/bash
# Pre-edit hook: navigate Obsidian away from the file before Claude edits it
# This prevents Obsidian's in-memory cache from overwriting the edit
#
# Dependencies: python3 (ships with macOS + Xcode CLT)

# Save tool input JSON to temp file (same pattern as post-edit hook)
HOOK_TMP=$(mktemp)
cat > "$HOOK_TMP"
trap 'rm -f "$HOOK_TMP"' EXIT

# Parse file_path with python3 (no jq dependency)
FILE_PATH=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get('tool_input', {}).get('file_path', ''))
" "$HOOK_TMP" 2>/dev/null)

# Only act on files inside an Obsidian vault
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Walk up to find .obsidian directory
SEARCH="$FILE_PATH"
VAULT_NAME=""
while [ "$SEARCH" != "/" ]; do
    SEARCH=$(dirname "$SEARCH")
    if [ -d "$SEARCH/.obsidian" ]; then
        VAULT_NAME=$(basename "$SEARCH")
        break
    fi
done

if [[ -z "$VAULT_NAME" ]]; then
    exit 0
fi

# Navigate Obsidian away from the file
ENCODED_VAULT=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$VAULT_NAME")
open "obsidian://open?vault=$ENCODED_VAULT" 2>/dev/null
sleep 0.5

exit 0
