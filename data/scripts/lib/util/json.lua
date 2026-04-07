-- Minimal JSON encoder/decoder for Avorion mod persistence.
-- Used to serialize complex tables to strings for setValue/getValue.
--
-- This is a lightweight, dependency-free implementation suitable for
-- Avorion's sandboxed Lua 5.1 environment.
--
-- Usage:
--   local json = include("util/json")
--   local str = json.encode({key = "value", num = 42})
--   local tbl = json.decode(str)

local json = {}

-- Encode --

local encode_value -- forward declaration

local function encode_string(val)
    val = val:gsub("\\", "\\\\")
    val = val:gsub('"', '\\"')
    val = val:gsub("\n", "\\n")
    val = val:gsub("\r", "\\r")
    val = val:gsub("\t", "\\t")
    return '"' .. val .. '"'
end

local function encode_table(val)
    -- Detect array vs object
    local is_array = true
    local n = 0
    for k, _ in pairs(val) do
        n = n + 1
        if type(k) ~= "number" or k ~= n then
            is_array = false
            break
        end
    end

    local parts = {}
    if is_array and n > 0 then
        for i = 1, #val do
            parts[i] = encode_value(val[i])
        end
        return "[" .. table.concat(parts, ",") .. "]"
    else
        local i = 0
        for k, v in pairs(val) do
            i = i + 1
            parts[i] = encode_string(tostring(k)) .. ":" .. encode_value(v)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
end

encode_value = function(val)
    local t = type(val)
    if t == "string" then
        return encode_string(val)
    elseif t == "number" then
        return tostring(val)
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "nil" then
        return "null"
    elseif t == "table" then
        return encode_table(val)
    else
        error("json.encode: unsupported type " .. t)
    end
end

function json.encode(val)
    return encode_value(val)
end

-- Decode --

local decode_value -- forward declaration

local function decode_string(str, pos)
    local start_char = str:sub(pos, pos)
    if start_char ~= '"' then
        error("json.decode: expected '\"' at position " .. pos)
    end
    pos = pos + 1
    local parts = {}
    while pos <= #str do
        local c = str:sub(pos, pos)
        if c == '"' then
            return table.concat(parts), pos + 1
        elseif c == "\\" then
            pos = pos + 1
            local esc = str:sub(pos, pos)
            if esc == "n" then
                parts[#parts + 1] = "\n"
            elseif esc == "r" then
                parts[#parts + 1] = "\r"
            elseif esc == "t" then
                parts[#parts + 1] = "\t"
            elseif esc == '"' then
                parts[#parts + 1] = '"'
            elseif esc == "\\" then
                parts[#parts + 1] = "\\"
            else
                parts[#parts + 1] = esc
            end
        else
            parts[#parts + 1] = c
        end
        pos = pos + 1
    end
    error("json.decode: unterminated string")
end

local function skip_whitespace(str, pos)
    while pos <= #str and str:sub(pos, pos):match("%s") do
        pos = pos + 1
    end
    return pos
end

local function decode_number(str, pos)
    local num_str = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    if not num_str then
        error("json.decode: invalid number at position " .. pos)
    end
    return tonumber(num_str), pos + #num_str
end

local function decode_array(str, pos)
    pos = pos + 1 -- skip '['
    local arr = {}
    pos = skip_whitespace(str, pos)
    if str:sub(pos, pos) == "]" then
        return arr, pos + 1
    end
    while true do
        local val
        val, pos = decode_value(str, pos)
        arr[#arr + 1] = val
        pos = skip_whitespace(str, pos)
        local c = str:sub(pos, pos)
        if c == "]" then
            return arr, pos + 1
        elseif c == "," then
            pos = skip_whitespace(str, pos + 1)
        else
            error("json.decode: expected ',' or ']' at position " .. pos)
        end
    end
end

local function decode_object(str, pos)
    pos = pos + 1 -- skip '{'
    local obj = {}
    pos = skip_whitespace(str, pos)
    if str:sub(pos, pos) == "}" then
        return obj, pos + 1
    end
    while true do
        local key
        key, pos = decode_string(str, pos)
        pos = skip_whitespace(str, pos)
        if str:sub(pos, pos) ~= ":" then
            error("json.decode: expected ':' at position " .. pos)
        end
        pos = skip_whitespace(str, pos + 1)
        local val
        val, pos = decode_value(str, pos)
        obj[key] = val
        pos = skip_whitespace(str, pos)
        local c = str:sub(pos, pos)
        if c == "}" then
            return obj, pos + 1
        elseif c == "," then
            pos = skip_whitespace(str, pos + 1)
        else
            error("json.decode: expected ',' or '}' at position " .. pos)
        end
    end
end

decode_value = function(str, pos)
    pos = skip_whitespace(str, pos)
    local c = str:sub(pos, pos)
    if c == '"' then
        return decode_string(str, pos)
    elseif c == "{" then
        return decode_object(str, pos)
    elseif c == "[" then
        return decode_array(str, pos)
    elseif c == "t" then
        if str:sub(pos, pos + 3) == "true" then
            return true, pos + 4
        end
    elseif c == "f" then
        if str:sub(pos, pos + 4) == "false" then
            return false, pos + 5
        end
    elseif c == "n" then
        if str:sub(pos, pos + 3) == "null" then
            return nil, pos + 4
        end
    elseif c == "-" or c:match("%d") then
        return decode_number(str, pos)
    end
    error("json.decode: unexpected character '" .. c .. "' at position " .. pos)
end

function json.decode(str)
    if type(str) ~= "string" then
        error("json.decode: expected string, got " .. type(str))
    end
    local val, _ = decode_value(str, 1)
    return val
end

return json
