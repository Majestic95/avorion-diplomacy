#!/bin/bash
# Run all tests for the EDE mod
# Usage: bash tools/test.sh [test_file]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LUA="$SCRIPT_DIR/lua/lua51/lua5.1.exe"

cd "$PROJECT_DIR"
"$LUA" tools/testrunner.lua "${1:-tests/}"
