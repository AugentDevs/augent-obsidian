#!/bin/bash
# Post-edit hook: sync Claude's edits to Obsidian via Local REST API
#
# Problem: Claude's Edit/Write tools write to disk. Obsidian detects
# the disk change and reverts the file to its in-memory cache within
# ~1-2 seconds. Reading the file after a disk write gets stale data.
#
# Solution: Block until Obsidian's revert settles (2s), then push the
# intended content through the REST API and wait for Obsidian to flush
# it back to disk. Must be synchronous (no background) so Claude sees
# correct content on the next read. Non-vault files exit instantly.
#
# Dependencies: python3, curl (both ship with macOS + Xcode CLT)

# Save tool input JSON to temp file (avoids ARG_MAX for large edits)
HOOK_TMP=$(mktemp)
cat > "$HOOK_TMP"
trap 'rm -f "$HOOK_TMP"' EXIT

# Parse tool_name and file_path with python3 (no jq dependency)
eval "$(python3 -c "
import json, sys, shlex
d = json.load(open(sys.argv[1]))
ti = d.get('tool_input', {})
print(f'TOOL_NAME={shlex.quote(d.get(\"tool_name\", \"\"))}')
print(f'FILE_PATH={shlex.quote(ti.get(\"file_path\", \"\"))}')
" "$HOOK_TMP" 2>/dev/null)"

if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Walk up to find .obsidian directory and vault root
SEARCH="$FILE_PATH"
VAULT_ROOT=""
while [ "$SEARCH" != "/" ]; do
    SEARCH=$(dirname "$SEARCH")
    if [ -d "$SEARCH/.obsidian" ]; then
        VAULT_ROOT="$SEARCH"
        break
    fi
done

# Not a vault file — exit instantly
if [[ -z "$VAULT_ROOT" ]]; then
    exit 0
fi

# Read API key from plugin config
API_KEY=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['apiKey'])" \
    "$VAULT_ROOT/.obsidian/plugins/obsidian-local-rest-api/data.json" 2>/dev/null)

if [[ -z "$API_KEY" ]]; then
    exit 0
fi

# Get vault-relative path and URL-encode it
REL_PATH="${FILE_PATH#$VAULT_ROOT/}"
ENCODED_REL=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$REL_PATH")
API_URL="https://localhost:27124/vault/$ENCODED_REL"

# Wait for Obsidian's revert cycle to finish
sleep 2

if [[ "$TOOL_NAME" == "Write" ]]; then
    # Write tool: extract content from tool_input and send directly
    python3 -c "
import json, sys
content = json.load(open(sys.argv[1])).get('tool_input', {}).get('content', '')
sys.stdout.write(content)
" "$HOOK_TMP" | curl -s --insecure \
        -X PUT \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: text/markdown" \
        --data-binary @- \
        "$API_URL" > /dev/null 2>&1

elif [[ "$TOOL_NAME" == "Edit" ]]; then
    # Edit tool: GET current content from Obsidian, apply replacement, PUT back
    CURRENT=$(curl -s --insecure \
        -H "Authorization: Bearer $API_KEY" \
        -H "Accept: text/markdown" \
        "$API_URL")

    # Apply old_string → new_string entirely in python3
    # Current content on stdin, tool input JSON read from temp file
    python3 -c "
import json, sys
current = sys.stdin.read()
d = json.load(open(sys.argv[1]))
ti = d.get('tool_input', {})
old = ti.get('old_string', '')
new = ti.get('new_string', '')
if not old:
    sys.exit(0)
if ti.get('replace_all', False):
    result = current.replace(old, new)
else:
    result = current.replace(old, new, 1)
sys.stdout.write(result)
" "$HOOK_TMP" <<< "$CURRENT" | curl -s --insecure \
        -X PUT \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: text/markdown" \
        --data-binary @- \
        "$API_URL" > /dev/null 2>&1
fi

# Give Obsidian a moment to flush the PUT back to disk
# so Claude's next read sees the correct content
sleep 0.5

exit 0
