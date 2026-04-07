-- Luacheck configuration for Avorion modding
-- See: https://luacheck.readthedocs.io/

std = "lua51"
max_line_length = 120

-- Avorion engine globals (C++-backed, available at runtime)
globals = {
    -- Core object constructors
    "Entity", "Sector", "Galaxy", "Player", "Server", "Faction",
    "Alliance", "AIFaction", "ScriptUI", "UIRenderer",

    -- Data types
    "TradingGood", "vec2", "vec3", "Rect", "Color", "Matrix", "Uuid", "Format",
    "GameSettings", "ChatMessageType", "RelationStatus",

    -- Avorion include system
    "include",

    -- Context functions
    "onServer", "onClient", "callable",
}

-- Allow self-defined globals in test files
files["tests/**/*.lua"] = {
    globals = {
        "describe", "it", "before_each", "after_each",
        "setup", "teardown", "pending", "spy", "stub", "mock",
        "assert", "_resetMocks",
    },
}

-- Allow mock globals in the mock file
files["tests/mocks/*.lua"] = {
    globals = {
        "_resetMocks",
    },
}

-- Ignore unused self parameter (common in Lua OOP)
ignore = { "212/self" }
