# Avorion: Economics & Diplomacy Expanded (EDE)

## Project Overview

A mod for Avorion (Steam space sandbox game) that adds economic warfare and advanced diplomacy mechanics. Players and AI factions can impose tariffs, negotiate trade agreements, declare embargoes, run blockades, conduct espionage, and engage in economic competition — with AI factions that dynamically respond to economic pressure.

- **Game:** Avorion (Steam, Boxelware)
- **Mod ID:** `avorion_ede`
- **Language:** Lua 5.1 (Avorion's embedded scripting engine)
- **Target:** Multiplayer-compatible (client/server architecture)
- **Philosophy:** Pure logic separated from engine calls; testable, reusable, extensible

---

## Avorion Install & Reference Paths

| Resource | Path |
|---|---|
| **Avorion install** | `F:\SteamLibrary\steamapps\common\Avorion` |
| **Vanilla scripts** | `F:\SteamLibrary\steamapps\common\Avorion\data\scripts\` |
| **API documentation** | `F:\SteamLibrary\steamapps\common\Avorion\Documentation\index.html` (270 HTML files) |
| **Mod install location** | `%AppData%\Roaming\Avorion\mods\` |
| **Galaxy saves** | `%AppData%\Roaming\Avorion\galaxies\<name>\` |
| **Client logs** | `%AppData%\Roaming\Avorion\clientlog <datetime>.txt` |
| **Server logs** | `%AppData%\Roaming\Avorion\galaxies\<name>\serverlog <datetime>.txt` |

### Key Vanilla Reference Files

These files are the most relevant to our mod and should be consulted before implementing related features:

| File | Purpose |
|---|---|
| `data/scripts/lib/goods.lua` | Trade goods definitions (name, price, size, tags) |
| `data/scripts/lib/goodsindex.lua` | Goods registry (all goods as a table) |
| `data/scripts/lib/tradingmanager.lua` | Station trade logic (buy/sell, pricing, supply/demand) |
| `data/scripts/lib/tradingutility.lua` | Trade helper functions |
| `data/scripts/lib/relations.lua` | Relation change types, caps, and named constants |
| `data/scripts/lib/faction.lua` | Faction state forms, archetypes (Corporate, Militaristic, etc.) |
| `data/scripts/lib/callable.lua` | Client/server RPC security declarations |
| `data/scripts/lib/entitydbg.lua` | Debug menu (reference for UI patterns) |
| `data/scripts/entity/merchants/` | All merchant station scripts (factory, consumer, trader, etc.) |

---

## Mod Structure

```
avorion-diplomacy/
├── CLAUDE.md                          # This file — project bible
├── modinfo.lua                        # Avorion mod metadata
├── .gitignore
├── .luacheckrc                        # Luacheck linter config
├── .stylua.toml                       # StyLua formatter config
├── .vscode/
│   ├── settings.json                  # Lua LSP config, Avorion globals
│   └── extensions.json                # Recommended VS Code extensions
├── data/
│   └── scripts/
│       ├── entity/                    # Scripts attached to ships/stations
│       ├── sector/                    # Scripts attached to sectors
│       ├── player/                    # Scripts attached to players
│       ├── commands/                  # Chat commands (e.g., /tariff, /embargo)
│       └── lib/
│           ├── diplomacy/             # Diplomatic state machine, proposals, AI reactions
│           │   └── states.lua         # Diplomatic state type definitions
│           ├── economy/               # Tariff calculations, trade hooks, market analysis
│           │   └── tariffs.lua        # Tariff/discount math (pure functions)
│           └── util/                  # Shared utilities
│               └── json.lua           # JSON encode/decode for setValue persistence
├── tests/
│   ├── mocks/
│   │   └── avorion.lua                # Mock Avorion API for out-of-game testing
│   ├── diplomacy/
│   │   └── states_test.lua            # Diplomatic states tests
│   └── economy/
│       └── tariffs_test.lua           # Tariff calculation tests
├── tools/                             # Dev utilities (test runners, linting scripts)
└── docs/                              # Design documents, feature specs
```

### File Organization Rules

- **`data/scripts/lib/`** — Pure logic modules. NO Avorion API calls (`Entity()`, `Sector()`, `Galaxy()`, etc.) allowed in this directory. These modules must be testable outside the game with busted + mocks.
- **`data/scripts/entity/`**, **`sector/`**, **`player/`** — Thin wrapper scripts that attach to game objects. These call Avorion APIs and delegate to lib modules for logic.
- **`tests/`** — Mirrors the `data/scripts/lib/` structure. Every lib module gets a corresponding test file.

---

## Avorion Modding Rules

These are non-negotiable constraints imposed by the Avorion engine:

1. **Always use `include()`, never `require()`** — `include()` is mod-aware and resolves extensions correctly. `require()` bypasses the mod system.
2. **Two-dot assignment trap** — `obj.position.x = 5` silently modifies a temporary copy. Always assign the full object: `obj.position = vec3(5, 0, 2)`. If there are two dots on the left side of an assignment with API objects, it is broken.
3. **Don't define empty callbacks** — An empty `update()` function is slower than no function. Only define `update()`, `updateParallelRead()`, `updateParallelWrite()` if you actually use them.
4. **Sector changes destroy client scripts** — Client-side Entity and Sector scripts are deleted and recreated on every sector transition. Never store persistent state in client-side local variables.
5. **`initUI()` is lazy** — Only called when the player interacts with the entity, not on script load. Don't put critical initialization there.
6. **`callable()` is mandatory for RPCs** — Every function exposed via `invokeServerFunction()` or `invokeClientFunction()` must be declared with `callable(context, functionName)` at the bottom of the script. Forgetting this is a silent failure.
7. **`setValue()` accepts only primitives** — string, number, boolean, nil. For tables, serialize to JSON string using `util/json.lua`. Never pass a table directly to `setValue()`.
8. **ASCII-only filenames** — Non-ASCII characters in file/folder names cause Steam Workshop upload to fail.
9. **Client filesystem is sandboxed** — No `io` library access on the client. All persistence must go through `setValue`/`getValue`.

---

## Coding Standards

### Lua Style

- **Indent:** 4 spaces (no tabs) — enforced by StyLua
- **Line length:** 120 characters max — enforced by StyLua and Luacheck
- **Naming:**
  - `snake_case` for variables, functions, file names
  - `PascalCase` for module tables (e.g., `local Tariffs = {}`)
  - `UPPER_SNAKE_CASE` for constants
  - File names: `kebab-case.lua` or `snake_case.lua` (prefer snake_case to match Avorion convention)
- **Strings:** Double quotes preferred (`"hello"` not `'hello'`) — enforced by StyLua
- **Module pattern:** Every lib file returns a single table. No pollution of the global namespace.

```lua
-- CORRECT: Module returns a table
local MyModule = {}

function MyModule.doThing(x)
    return x * 2
end

return MyModule
```

```lua
-- WRONG: Pollutes global namespace
function doThing(x)
    return x * 2
end
```

### File Size Limits

- **Soft cap: 300 lines** — evaluate whether the file should be split
- **Hard cap: 500 lines** — must be split before committing. No exceptions.
- **Test files are exempt** from line limits.

### Code Quality

- **No dead code** — delete unused functions, commented-out blocks, unreachable code
- **No `print()` in committed code** — use `print()` for debugging, remove before commit. Mods that spam the console are bad citizens.
- **Comments explain WHY, not WHAT** — the code shows what; comments explain the reasoning
- **Every lib module requires tests** — a module without tests is incomplete
- **Validate at boundaries only** — validate user input and external data (trade callbacks, RPC arguments). Don't validate internal function calls between our own modules.
- **Prefer early returns** — reduce nesting with guard clauses

### Error Handling

- **Never swallow errors silently** — if a function can fail, handle the failure visibly (log or propagate)
- **Use `eprint()` for errors** — `eprint()` routes to error output; `print()` is informational
- **Defensive RPC handling** — every `invokeServerFunction` handler must validate its arguments. Clients can send anything.

---

## Architecture Principles

1. **Pure logic / engine wrapper split** — All calculations, state machines, and decision logic live in `data/scripts/lib/` with zero Avorion API calls. Engine-touching code (entity scripts, sector scripts) is a thin shell that calls lib functions. This is the single most important architecture decision — it makes the mod testable.

2. **Server-authoritative** — All diplomatic state changes, tariff calculations, and economic effects happen server-side. Client scripts only display UI and send requests via `invokeServerFunction()`.

3. **Persistence via JSON + setValue** — Complex state (diplomatic agreements, tariff schedules, faction AI memory) is serialized to JSON strings and stored with `Galaxy():setValue()` or `Faction():setValue()`. Never rely on in-memory state surviving a server restart.

4. **Additive, not destructive** — We never modify vanilla scripts directly. Our mod layers behavior on top through entity scripts, callbacks, and hooks. Players can disable the mod without breaking their save.

5. **Faction-archetype-aware** — Avorion factions have archetypes (Corporate, Militaristic, Religious, etc.). Our diplomacy/economic AI should respect these — a Corporate faction should be more trade-oriented, a Militaristic faction more blockade-prone.

6. **Reusable by design** — Other modders should be able to `include()` our lib modules independently. `diplomacy/states.lua` and `economy/tariffs.lua` should work as standalone libraries.

---

## Development Workflow

### Before Writing Any Code

This is mandatory for every change, no matter how small:

1. **Explain the approach** — describe what will change, which files will be touched, and the expected behavior
2. **Impact analysis — what could break** — for EVERY change, explicitly list:
   - Which existing systems could be affected
   - Which callbacks or hooks might behave differently
   - Edge cases that could cause unexpected behavior
   - Save compatibility implications (does this change how data is persisted?)
   - Multiplayer implications (does this affect client/server sync?)
   - Interaction with vanilla Avorion mechanics (could this conflict with base game behavior?)
   - Performance implications (does this run per-tick? per-trade? once?)
3. **Define scope lock** — explicitly state what IS and IS NOT in scope. No "while I'm here" side-effects.
4. **Get confirmation** — wait for approval before coding

### While Building

- **Update CLAUDE.md in real time** — when you discover an Avorion quirk, solve a tricky bug, or establish a pattern, document it immediately in "Stack Notes & Patterns Learned"
- **One concern per commit** — a bug fix and a feature are two commits
- **Checkpoint commit before fixes** — always commit working state before attempting a fix. Never debug on a dirty working tree.

### Before Every Commit

**Pre-commit checklist (all must pass):**
```bash
# From project root (F:\avorion-diplomacy)
bash tools/check.sh      # Runs lint + tests (zero warnings, all tests pass)

# Or individually:
bash tools/lint.sh        # Zero luacheck warnings
bash tools/test.sh        # All tests pass
```

### After Every Feature

**Mandatory review before commit:**
1. **Logic correctness** — verify business logic, edge cases, off-by-one errors
2. **Avorion API usage** — verify no API calls in lib/ modules, correct use of `include()`, `callable()` declarations present
3. **Persistence safety** — verify `setValue`/`getValue` round-trips are correct, JSON serialization handles edge cases
4. **Client/server split** — verify gameplay logic is server-side only, UI code is client-side only
5. **Performance** — verify no unnecessary per-tick operations, no sector scanning in hot paths
6. **Save compatibility** — verify changes don't break existing saves (new fields have defaults)

### Impact Analysis — What Could Break

**This is non-negotiable. Every change gets an explicit "what could break" analysis.**

The analysis must cover:
- **Direct effects** — what this change is supposed to do
- **Side effects** — what else might change as a consequence
- **Regression risk** — what previously-working behavior might break
- **Data risk** — can this corrupt persisted data or break save compatibility
- **Multiplayer risk** — can this desync client and server state
- **Vanilla interaction risk** — can this conflict with base Avorion mechanics

If a change has no identified risks, say so explicitly — "No risks identified: this is a pure addition with no interaction with existing code." Don't skip the analysis just because it seems safe.

---

## Testing

### Architecture: Testable by Design

The mod is architected so that all game logic lives in pure Lua modules (`data/scripts/lib/`) with no Avorion engine dependencies. These modules are tested out-of-game using **busted** (a Lua BDD testing framework) with lightweight API mocks.

```
┌─────────────────────────┐
│   Entity/Sector Scripts │  ← Thin wrappers (tested in-game only)
│   (Avorion API calls)   │
├─────────────────────────┤
│   Lib Modules           │  ← Pure logic (tested with busted)
│   (no API calls)        │
└─────────────────────────┘
```

### Running Tests

```bash
# Run all tests
bash tools/test.sh

# Run a specific test file
bash tools/test.sh tests/economy/tariffs_test.lua

# Or invoke directly with Lua 5.1:
tools/lua/lua51/lua5.1.exe tools/testrunner.lua tests/
```

### Writing Tests

- Test files live in `tests/` mirroring the `data/scripts/lib/` structure
- File naming: `<module_name>_test.lua`
- Always `dofile("tests/mocks/avorion.lua")` at the top of each test file
- Always call `_resetMocks()` in `before_each`
- Use `include()` from the mock to load modules under test (resolves via `data/scripts/lib/`)

```lua
dofile("tests/mocks/avorion.lua")

describe("MyModule", function()
    local MyModule

    before_each(function()
        _resetMocks()
        MyModule = include("mymodule")
    end)

    it("does the thing", function()
        assert.are.equal(expected, MyModule.doThing(input))
    end)
end)
```

### In-Game Testing

For scripts that touch the Avorion API (entity scripts, UI, callbacks):

1. Create a test galaxy with `InfiniteResources=true`, `StartingResources=-4`, `FullBuildingUnlocked=true`
2. Enable Dev Mode checkbox in Settings > Mods
3. Run `/devmode` and restart
4. Use `/run` for ad-hoc Lua execution
5. Use `entitydbg.lua` for entity inspection and faction manipulation
6. Press **F6** to reload client-side scripts without restarting

**Key test commands:**
```
/run Galaxy():changeFactionRelations(Player(), factionIdx, value)
/run Entity():addScript("lib/entitydbg.lua")
/give PlayerName 999999 credits
/teleport PlayerName X Y
```

---

## Persistence Patterns

### Simple Values
```lua
-- Store on a faction
Faction():setValue("ede_tariff_rate", 0.15)
local rate = Faction():getValue("ede_tariff_rate") or 0
```

### Complex State (JSON)
```lua
local json = include("util/json")

-- Store diplomatic state between two factions
local key = "ede_diplo_" .. factionA.index .. "_" .. factionB.index
local state = {
    type = "tariff",
    rate = 0.15,
    imposed_tick = Server().unpausedRuntime,
}
Galaxy():setValue(key, json.encode(state))

-- Retrieve
local raw = Galaxy():getValue(key)
if raw then
    local state = json.decode(raw)
end
```

### Key Naming Convention
All mod keys are prefixed with `ede_` to avoid collisions with other mods:
- `ede_diplo_<factionA>_<factionB>` — bilateral diplomatic state
- `ede_tariff_<factionA>_<factionB>` — tariff rate between factions
- `ede_ai_memory_<faction>` — faction AI decision memory
- `ede_config` — global mod configuration

---

## Client/Server Script Pattern

```lua
-- === SERVER SIDE ===
package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

local Tariffs = include("economy/tariffs")

function MyScript.onBought(good, amount, price)
    if onServer() then
        local surcharge = Tariffs.calculateSurcharge(price, getTariffRate())
        -- Apply surcharge logic...
        broadcastInvokeClientFunction("onTradeNotification", good, surcharge)
    end
end

-- === CLIENT SIDE ===
function MyScript.onTradeNotification(good, surcharge)
    if onClient() then
        -- Update UI...
    end
end

-- === RPC DECLARATIONS (bottom of file) ===
callable(nil, "onTradeNotification")
```

---

## Git Conventions

### Branching
- `main` — stable, release-ready
- `feature/<name>` — feature branches
- `fix/<name>` — bug fix branches

### Commit Messages
[Conventional Commits](https://www.conventionalcommits.org/):
```
<type>(<scope>): <short description>
```
**Types:** `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`
**Scopes:** `diplomacy`, `economy`, `ui`, `ai`, `persistence`, `tests`, `tooling`

### Examples
```
feat(economy): add tariff surcharge calculation
test(economy): add tariff edge case tests for rate capping
fix(diplomacy): prevent duplicate embargo entries on save/load
docs: update CLAUDE.md with persistence patterns
```

---

## Tooling

### Bundled Tools (in `tools/`)

All tools are bundled in the repo so contributors don't need to install anything beyond VS Code:

| Tool | Location | Purpose |
|---|---|---|
| **Lua 5.1.5** | `tools/lua/lua51/lua5.1.exe` | Runtime for tests (matches Avorion's embedded Lua) |
| **Luacheck 1.2.0** | `tools/luacheck.exe` | Static analyzer / linter (standalone binary) |
| **Test runner** | `tools/testrunner.lua` | Minimal busted-compatible test framework (pure Lua, zero deps) |

### Optional Tools (install separately)

| Tool | Purpose | Install |
|---|---|---|
| **StyLua** | Lua code formatter | VS Code extension `JohnnyMorganz.stylua` or `cargo install stylua` |
| **sumneko lua-language-server** | LSP for VS Code | VS Code extension `sumneko.lua` |

### Convenience Scripts

```bash
bash tools/test.sh              # Run all tests
bash tools/test.sh tests/economy/tariffs_test.lua  # Run one test file
bash tools/lint.sh              # Run luacheck linter
bash tools/check.sh             # Run lint + tests (pre-commit)
```

### VS Code Setup

Install recommended extensions (prompted automatically via `.vscode/extensions.json`):
- `sumneko.lua` — Lua language server (intellisense, diagnostics, go-to-definition)
- `JohnnyMorganz.stylua` — Lua formatter (format on save configured)

Settings are pre-configured in `.vscode/settings.json`:
- Lua 5.1 runtime target
- Avorion script directories added to workspace library (enables autocomplete for vanilla APIs)
- All Avorion globals declared (no false "undefined global" warnings)
- Format on save enabled with StyLua

---

## Stack Notes & Patterns Learned

_This section is updated in real time as patterns are discovered. Each entry includes the date and context._

- **Avorion uses Lua 5.1** (2026-04-07): Not 5.3 or 5.4. No integer type, no bitwise operators, no goto. Use `math.floor()` for integer math. String patterns, not regex.
- **`package.path` must be set before `include()`** (2026-04-07): Vanilla scripts prepend `package.path = package.path .. ";data/scripts/lib/?.lua"` at the top. Our scripts must do the same.
- **Vanilla `relations.lua` defines `RelationChangeType` enum** (2026-04-07): Commerce-related types include `ServiceUsage`, `ResourceTrade`, `GoodsTrade`, `EquipmentTrade`, `WeaponsTrade`, `Commerce`, each with relation caps (max 45K-75K). Our trade hooks should use these types when modifying relations.
- **Vanilla `faction.lua` defines `FactionArchetype`** (2026-04-07): 8 archetypes (Vanilla, Traditional, Independent, Militaristic, Religious, Corporate, Alliance, Sect) mapped from 22 `FactionStateFormType`s. Our AI should key behavior off archetypes.
- **`TradingManager` has `relationsThreshold` field** (2026-04-07): Vanilla already supports a minimum relations threshold for trade. Our embargo system may be able to leverage this rather than reimplementing access control.
- **`TradingManager.tax` field** (2026-04-07): Vanilla has a per-station tax rate (owner gets % of transactions). Our tariff system can potentially layer on top of or work alongside this.

---

## Feature Roadmap

### V0.1 — Tariffs + Trade Agreements (Vertical Slice)
- [ ] Tariff data model and state persistence
- [ ] Trade agreement data model and state persistence
- [ ] `onBought`/`onSold` hooks that apply tariff surcharges
- [ ] Trade agreement discount hooks
- [ ] Basic diplomacy UI panel (propose/view/cancel agreements)
- [ ] One AI faction behavior: retaliatory tariffs
- [ ] Tests for all pure logic modules

### V0.2 — Embargoes + Sanctions
- [ ] Embargo state type with full trade blocking
- [ ] Multi-faction sanctions (coordinated embargoes)
- [ ] Faction AI: embargo response behaviors
- [ ] Smuggling mechanic (trade during embargo at high risk)
- [ ] Notifications system for diplomatic events

### V0.3 — Blockades + Espionage
- [ ] Physical blockade system (patrol fleets)
- [ ] Espionage mechanic (reveal enemy economic data)
- [ ] Intelligence UI panel
- [ ] Escalation state machine (tariff → embargo → blockade → war)
- [ ] Faction AI: economic strategy based on archetype

### Future
- [ ] Trade route visualization on galaxy map
- [ ] Economic overview dashboard
- [ ] Custom goods (contraband during embargoes)
- [ ] Alliance-level diplomatic actions
- [ ] Steam Workshop publication
