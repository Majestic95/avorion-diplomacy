-- EDE Territory Cache
-- Pure data module — no Avorion API calls (testable outside the game)
--
-- Manages a cache of faction → sector count mappings.
-- The actual scanning of sectors (calling Galaxy():getControllingFaction)
-- is done by an engine script that feeds results into this module.

local Territory = {}

-- Cache structure: { [faction_index] = sector_count }
local cache = {}
local cache_timestamp = 0

--- Reset the cache (used between scan cycles and in tests).
function Territory.reset()
    cache = {}
    cache_timestamp = 0
end

--- Set the sector count for a faction. Called by the engine scanner.
--- @param faction_index number The faction's index
--- @param count number The number of sectors controlled
function Territory.setCount(faction_index, count)
    cache[faction_index] = math.max(count or 0, 0)
end

--- Increment the sector count for a faction by 1.
--- @param faction_index number The faction's index
function Territory.increment(faction_index)
    cache[faction_index] = (cache[faction_index] or 0) + 1
end

--- Get the sector count for a faction.
--- @param faction_index number The faction's index
--- @return number count The number of sectors controlled (0 if unknown)
function Territory.getCount(faction_index)
    return cache[faction_index] or 0
end

--- Get the full cache (all faction → count pairs).
--- @return table cache Copy of the current cache
function Territory.getAll()
    local copy = {}
    for k, v in pairs(cache) do
        copy[k] = v
    end
    return copy
end

--- Set the cache timestamp (seconds since server start or epoch).
--- @param timestamp number The time the cache was last refreshed
function Territory.setTimestamp(timestamp)
    cache_timestamp = timestamp or 0
end

--- Get the cache timestamp.
--- @return number timestamp When the cache was last refreshed
function Territory.getTimestamp()
    return cache_timestamp
end

--- Check if the cache is stale (older than max_age seconds).
--- @param current_time number The current time
--- @param max_age number Maximum age in seconds before cache is stale
--- @return boolean stale Whether the cache needs refreshing
function Territory.isStale(current_time, max_age)
    if cache_timestamp == 0 then
        return true
    end
    return (current_time - cache_timestamp) >= max_age
end

--- Build a scan grid of sector coordinates around a center point.
--- Used by the engine scanner to know which sectors to check.
--- @param center_x number Center X coordinate
--- @param center_y number Center Y coordinate
--- @param radius number How far from center to scan
--- @param step number Grid step size (larger = faster but less accurate)
--- @return table coords Array of {x, y} pairs to scan
function Territory.buildScanGrid(center_x, center_y, radius, step)
    step = step or 10
    local coords = {}
    for x = center_x - radius, center_x + radius, step do
        for y = center_y - radius, center_y + radius, step do
            coords[#coords + 1] = { x = x, y = y }
        end
    end
    return coords
end

return Territory
