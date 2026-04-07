# Avorion: Economics & Diplomacy Expanded (EDE)

A mod for [Avorion](https://store.steampowered.com/app/445220/Avorion/) that adds economic warfare and advanced diplomacy mechanics. Players and AI factions can impose tariffs, negotiate trade agreements, declare embargoes, run blockades, conduct espionage, and engage in economic competition.

## Features (Planned)

- **Tariffs** — Import/export taxes between factions
- **Trade Agreements** — Discounted trade with allied factions
- **Embargoes** — Full trade blocks between hostile factions
- **Sanctions** — Multi-faction coordinated embargoes
- **Blockades** — Physical trade route denial with patrol fleets
- **Espionage** — Reveal enemy economic data
- **AI Reactions** — Factions dynamically respond to economic pressure based on their archetype (Corporate, Militaristic, etc.)

## Installation

1. Download or subscribe via Steam Workshop (TBD)
2. Enable in Settings > Mods
3. Start or load a galaxy

## For Developers

### Prerequisites

- [Avorion](https://store.steampowered.com/app/445220/Avorion/) installed
- Git
- VS Code (recommended) with Lua extensions

### Setup

```bash
git clone https://github.com/Majestic95/avorion-diplomacy.git
cd avorion-diplomacy
bash tools/setup.sh    # Downloads Lua 5.1 and Luacheck
bash tools/check.sh    # Verify: lint + tests
```

### Development Commands

```bash
bash tools/test.sh     # Run all tests (15 tests)
bash tools/lint.sh     # Run Luacheck linter
bash tools/check.sh    # Run both (pre-commit)
```

### Architecture

The mod is designed for **testability** and **reusability**:

- `data/scripts/lib/` — Pure logic modules (no Avorion API calls, testable outside the game)
- `data/scripts/entity/` — Thin wrapper scripts that attach to game objects
- `tests/` — Out-of-game tests using a lightweight busted-compatible runner

Other modders can `include()` our lib modules independently for their own mods.

See [CLAUDE.md](CLAUDE.md) for full coding standards, architecture decisions, and development workflow.

## License

MIT
