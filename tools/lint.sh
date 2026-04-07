#!/bin/bash
# Run luacheck linter on all mod code
# Usage: bash tools/lint.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LUACHECK="$SCRIPT_DIR/luacheck.exe"

cd "$PROJECT_DIR"

# Collect all .lua files (luacheck directory scanning has issues on Windows)
FILES=$(find data/scripts/lib tests -name "*.lua" -type f 2>/dev/null)
if [ -z "$FILES" ]; then
    # Fallback for Windows
    FILES=$(find data/scripts/lib tests -name "*.lua" 2>/dev/null)
fi

if [ -z "$FILES" ]; then
    echo "No Lua files found to lint"
    exit 1
fi

echo $FILES | xargs "$LUACHECK"
