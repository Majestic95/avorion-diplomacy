#!/bin/bash
# Run full pre-commit checks: lint + test
# Usage: bash tools/check.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Linting ==="
bash "$SCRIPT_DIR/lint.sh"

echo ""
echo "=== Tests ==="
bash "$SCRIPT_DIR/test.sh"

echo ""
echo "=== All checks passed ==="
