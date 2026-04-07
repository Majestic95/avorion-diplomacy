#!/bin/bash
# Download and set up development tools for EDE mod development.
# Run this once after cloning the repo.
# Usage: bash tools/setup.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Setting up EDE development tools ==="

# 1. Lua 5.1 (prebuilt binaries from LuaBinaries)
if [ ! -f "lua/lua51/lua5.1.exe" ]; then
    echo "Downloading Lua 5.1.5..."
    mkdir -p lua/lua51
    curl -L -o lua/lua51.zip "https://sourceforge.net/projects/luabinaries/files/5.1.5/Tools%20Executables/lua-5.1.5_Win64_bin.zip/download"
    cd lua/lua51 && unzip -o ../lua51.zip && rm ../lua51.zip && cd "$SCRIPT_DIR"
    echo "  Lua 5.1.5 installed at tools/lua/lua51/"
else
    echo "  Lua 5.1.5 already installed"
fi

# 2. Luacheck (standalone binary from GitHub)
if [ ! -f "luacheck.exe" ]; then
    echo "Downloading Luacheck 1.2.0..."
    curl -L -o luacheck.exe "https://github.com/lunarmodules/luacheck/releases/download/v1.2.0/luacheck.exe"
    echo "  Luacheck 1.2.0 installed at tools/luacheck.exe"
else
    echo "  Luacheck 1.2.0 already installed"
fi

echo ""
echo "=== Setup complete ==="
echo "Run 'bash tools/check.sh' to verify everything works."
echo ""
echo "Optional: Install VS Code extensions for best experience:"
echo "  - sumneko.lua (Lua language server)"
echo "  - JohnnyMorganz.stylua (Lua formatter)"
