-- EDE Persistence Layer
-- Pure logic module — no Avorion API calls (testable outside the game)
--
-- Provides a storage abstraction that serializes/deserializes tables to JSON.
-- Engine scripts pass in a "store" object (e.g., Galaxy(), Faction()) that
-- has setValue(key, value) and getValue(key) methods.
--
-- All keys are prefixed with "ede_" to avoid collisions with other mods.

package.path = package.path .. ";data/scripts/lib/?.lua"

local json = include("util/json")

local Persistence = {}

local KEY_PREFIX = "ede_"

--- Build a prefixed key.
--- @param key string The unprefixed key
--- @return string The prefixed key
function Persistence.key(key)
    return KEY_PREFIX .. key
end

--- Save a table (or primitive) to a store object.
--- Tables are JSON-serialized. Primitives are stored directly.
--- @param store table Object with setValue(key, value) method
--- @param key string The key (will be auto-prefixed with "ede_")
--- @param value any The value to store (table, string, number, boolean, or nil)
function Persistence.save(store, key, value)
    local full_key = Persistence.key(key)
    if type(value) == "table" then
        store:setValue(full_key, json.encode(value))
    else
        store:setValue(full_key, value)
    end
end

--- Load a value from a store object.
--- Attempts JSON deserialization for string values that look like JSON.
--- @param store table Object with getValue(key) method
--- @param key string The key (will be auto-prefixed with "ede_")
--- @return any value The stored value (deserialized table, or primitive)
function Persistence.load(store, key)
    local full_key = Persistence.key(key)
    local raw = store:getValue(full_key)
    if raw == nil then
        return nil
    end
    if type(raw) == "string" then
        local first = raw:sub(1, 1)
        if first == "{" or first == "[" then
            local ok, result = pcall(json.decode, raw)
            if ok then
                return result
            end
        end
    end
    return raw
end

--- Delete a key from a store object.
--- @param store table Object with setValue(key, value) method
--- @param key string The key (will be auto-prefixed with "ede_")
function Persistence.delete(store, key)
    local full_key = Persistence.key(key)
    store:setValue(full_key, nil)
end

--- Save a bilateral state (between two factions).
--- Key format: ede_<prefix>_<factionA>_<factionB> (sorted so A < B for consistency)
--- @param store table Object with setValue method
--- @param prefix string The state type prefix (e.g., "tariff", "agreement")
--- @param faction_a number First faction index
--- @param faction_b number Second faction index
--- @param value any The value to store
function Persistence.saveBilateral(store, prefix, faction_a, faction_b, value)
    local a = math.min(faction_a, faction_b)
    local b = math.max(faction_a, faction_b)
    local key = prefix .. "_" .. a .. "_" .. b
    Persistence.save(store, key, value)
end

--- Load a bilateral state.
--- @param store table Object with getValue method
--- @param prefix string The state type prefix
--- @param faction_a number First faction index
--- @param faction_b number Second faction index
--- @return any value The stored value
function Persistence.loadBilateral(store, prefix, faction_a, faction_b)
    local a = math.min(faction_a, faction_b)
    local b = math.max(faction_a, faction_b)
    local key = prefix .. "_" .. a .. "_" .. b
    return Persistence.load(store, key)
end

--- Delete a bilateral state.
--- @param store table Object with setValue method
--- @param prefix string The state type prefix
--- @param faction_a number First faction index
--- @param faction_b number Second faction index
function Persistence.deleteBilateral(store, prefix, faction_a, faction_b)
    local a = math.min(faction_a, faction_b)
    local b = math.max(faction_a, faction_b)
    local key = prefix .. "_" .. a .. "_" .. b
    Persistence.delete(store, key)
end

return Persistence
