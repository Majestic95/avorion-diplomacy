-- Mock Avorion API for out-of-game testing with busted.
-- This provides lightweight stubs for core Avorion globals so that
-- pure logic modules can be required and tested without the game engine.
--
-- Usage (in a test file):
--   require("tests.mocks.avorion")
--   local MyModule = dofile("data/scripts/lib/diplomacy/states.lua")
--
-- Only stub what is needed. Add new stubs as modules grow.

-- Replace Avorion's include() with a standard dofile-based loader
function include(path)
    -- Try multiple resolution paths (mirrors Avorion's search order)
    local candidates = {
        "data/scripts/lib/" .. path .. ".lua",
        "data/scripts/" .. path .. ".lua",
        path .. ".lua",
        path,
    }
    for _, candidate in ipairs(candidates) do
        local f = io.open(candidate, "r")
        if f then
            f:close()
            return dofile(candidate)
        end
    end
    error("include(): could not find module '" .. path .. "'")
end

-- Context stubs
function onServer()
    return true
end

function onClient()
    return false
end

function callable(_, _) end

-- Stub constructors (return plain tables)
function vec2(x, y)
    return { x = x or 0, y = y or 0 }
end

function vec3(x, y, z)
    return { x = x or 0, y = y or 0, z = z or 0 }
end

function Color(r, g, b, a)
    return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 }
end

function Rect(x, y, w, h)
    return { lower = vec2(x, y), upper = vec2(x + w, y + h) }
end

-- Key-value store mock (simulates setValue/getValue on any object)
local ValueStoreMixin = {}
function ValueStoreMixin:setValue(key, value)
    self._values = self._values or {}
    self._values[key] = value
end
function ValueStoreMixin:getValue(key)
    self._values = self._values or {}
    return self._values[key]
end

-- Entity mock
local entity_instance = setmetatable({}, { __index = ValueStoreMixin })
function Entity()
    return entity_instance
end

-- Sector mock
local sector_instance = setmetatable({}, { __index = ValueStoreMixin })
function Sector()
    return sector_instance
end

-- Galaxy mock (NOTE: real Avorion Galaxy() does NOT have setValue/getValue)
local galaxy_instance = {}
function Galaxy()
    return galaxy_instance
end

-- Server mock (this is the correct global persistence store in Avorion)
local server_instance = setmetatable({}, { __index = ValueStoreMixin })
function Server()
    return server_instance
end

-- Player mock
local player_instance = setmetatable({}, { __index = ValueStoreMixin })
player_instance.index = 1
function Player()
    return player_instance
end

-- Faction mock
local faction_instance = setmetatable({}, { __index = ValueStoreMixin })
faction_instance.index = 100
function Faction()
    return faction_instance
end

-- Reset all mocks (call in before_each)
function _resetMocks()
    entity_instance._values = {}
    sector_instance._values = {}
    server_instance._values = {}
    player_instance._values = {}
    faction_instance._values = {}
end
