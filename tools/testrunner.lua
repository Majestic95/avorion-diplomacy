-- Minimal busted-compatible test runner for Avorion mod development.
-- Runs on vanilla Lua 5.1 with zero external dependencies.
--
-- Usage: lua5.1 tools/testrunner.lua [test_file_or_directory]
--
-- Supports: describe(), it(), before_each(), after_each(), assert.*
-- This is intentionally minimal — just enough to test pure logic modules.

local passed = 0
local failed = 0
local errors = {}
local current_describe = ""
local before_each_fn = nil
local after_each_fn = nil

-- Color codes (ANSI)
local GREEN = "\27[32m"
local RED = "\27[31m"
local YELLOW = "\27[33m"
local RESET = "\27[0m"
local DIM = "\27[2m"

function describe(name, fn)
    local parent_describe = current_describe
    local parent_before = before_each_fn
    local parent_after = after_each_fn
    current_describe = (parent_describe ~= "" and parent_describe .. " > " or "") .. name
    -- Inherit parent's before_each/after_each (child can override)
    fn()
    current_describe = parent_describe
    before_each_fn = parent_before
    after_each_fn = parent_after
end

function it(name, fn)
    local full_name = current_describe .. " > " .. name
    if before_each_fn then
        before_each_fn()
    end
    local ok, err = pcall(fn)
    if after_each_fn then
        pcall(after_each_fn)
    end
    if ok then
        passed = passed + 1
        io.write(GREEN .. "  PASS " .. RESET .. DIM .. full_name .. RESET .. "\n")
    else
        failed = failed + 1
        table.insert(errors, { name = full_name, error = err })
        io.write(RED .. "  FAIL " .. RESET .. full_name .. "\n")
        io.write(RED .. "       " .. tostring(err) .. RESET .. "\n")
    end
end

function before_each(fn)
    before_each_fn = fn
end

function after_each(fn)
    after_each_fn = fn
end

function setup(fn)
    fn()
end

function teardown(fn)
    -- Run at end of describe (simplified: just run immediately)
end

function pending(name)
    io.write(YELLOW .. "  SKIP " .. RESET .. DIM .. current_describe .. " > " .. name .. RESET .. "\n")
end

-- Assert library (busted-compatible subset)
assert = assert or {}
local raw_assert = assert

local assert_mt = {}
assert_mt.__index = assert_mt

-- assert.are.equal(expected, actual)
-- assert.is_true(val)
-- assert.is_false(val)
-- assert.is_nil(val)
-- assert.is_not_nil(val)
-- assert.is_number(val)
-- assert.is_string(val)
-- assert.has_error(fn)

local function make_assert()
    local a = {}

    a.are = {}
    a.is = a
    a.is_not = {}
    a.has = {}

    function a.are.equal(expected, actual, msg)
        if expected ~= actual then
            error(string.format(
                "Expected %s but got %s%s",
                tostring(expected),
                tostring(actual),
                msg and (" — " .. msg) or ""
            ), 2)
        end
    end

    function a.are.same(expected, actual)
        -- Deep equality for tables
        if type(expected) == "table" and type(actual) == "table" then
            for k, v in pairs(expected) do
                if actual[k] ~= v then
                    error(string.format("Tables differ at key '%s': expected %s, got %s", tostring(k), tostring(v), tostring(actual[k])), 2)
                end
            end
            for k, _ in pairs(actual) do
                if expected[k] == nil then
                    error(string.format("Unexpected key '%s' in actual table", tostring(k)), 2)
                end
            end
        elseif expected ~= actual then
            error(string.format("Expected %s but got %s", tostring(expected), tostring(actual)), 2)
        end
    end

    function a.is_true(val, msg)
        if val ~= true then
            error(string.format("Expected true but got %s%s", tostring(val), msg and (" — " .. msg) or ""), 2)
        end
    end

    function a.is_false(val, msg)
        if val ~= false then
            error(string.format("Expected false but got %s%s", tostring(val), msg and (" — " .. msg) or ""), 2)
        end
    end

    function a.is_nil(val, msg)
        if val ~= nil then
            error(string.format("Expected nil but got %s%s", tostring(val), msg and (" — " .. msg) or ""), 2)
        end
    end

    function a.is_not_nil(val, msg)
        if val == nil then
            error(string.format("Expected non-nil value%s", msg and (" — " .. msg) or ""), 2)
        end
    end

    function a.is_number(val)
        if type(val) ~= "number" then
            error(string.format("Expected number but got %s (%s)", type(val), tostring(val)), 2)
        end
    end

    function a.is_string(val)
        if type(val) ~= "string" then
            error(string.format("Expected string but got %s (%s)", type(val), tostring(val)), 2)
        end
    end

    function a.is_table(val)
        if type(val) ~= "table" then
            error(string.format("Expected table but got %s (%s)", type(val), tostring(val)), 2)
        end
    end

    function a.has_error(fn)
        local ok, _ = pcall(fn)
        if ok then
            error("Expected function to throw an error but it didn't", 2)
        end
    end

    -- Make assert() itself still work as a function
    setmetatable(a, {
        __call = function(_, val, msg)
            if not val then
                error(msg or "assertion failed", 2)
            end
        end,
    })

    return a
end

assert = make_assert()

-- File discovery
local function is_test_file(path)
    return path:match("_test%.lua$") ~= nil
end

local function find_test_files(dir)
    local files = {}
    -- Normalize path separators for the OS
    dir = dir:gsub("\\", "/")
    -- Try Unix find first, fall back to Windows dir command
    local cmd = string.format('find "%s" -name "*_test.lua" -type f 2>/dev/null', dir)
    local handle = io.popen(cmd)
    if handle then
        for line in handle:lines() do
            if line:match("_test%.lua$") then
                table.insert(files, line)
            end
        end
        handle:close()
    end
    -- Fallback: Windows dir command
    if #files == 0 then
        cmd = string.format('dir /s /b "%s\\*_test.lua" 2>nul', dir:gsub("/", "\\"))
        handle = io.popen(cmd)
        if handle then
            -- Get current working directory to make paths relative
            local cwd_handle = io.popen("cd")
            local cwd = cwd_handle and cwd_handle:read("*l") or ""
            if cwd_handle then cwd_handle:close() end
            cwd = cwd:gsub("\\", "/")
            if cwd:sub(-1) ~= "/" then cwd = cwd .. "/" end

            for line in handle:lines() do
                line = line:gsub("\\", "/")
                -- Strip CWD prefix to get relative path
                if cwd ~= "/" and line:sub(1, #cwd) == cwd then
                    line = line:sub(#cwd + 1)
                end
                if line:match("_test%.lua$") then
                    table.insert(files, line)
                end
            end
            handle:close()
        end
    end
    return files
end

-- Main
local function run()
    local target = arg[1] or "tests/"

    local files = {}

    -- Check if target is a file or directory
    local f = io.open(target, "r")
    if f then
        f:close()
        if is_test_file(target) then
            files = { target }
        else
            files = find_test_files(target)
        end
    else
        files = find_test_files(target)
    end

    if #files == 0 then
        print(YELLOW .. "No test files found in: " .. target .. RESET)
        os.exit(1)
    end

    print("")
    print("Running " .. #files .. " test file(s)...")
    print(string.rep("-", 60))

    for _, file in ipairs(files) do
        print("\n" .. DIM .. file .. RESET)
        -- Reset state for each file
        before_each_fn = nil
        after_each_fn = nil
        current_describe = ""

        local ok, err = pcall(dofile, file)
        if not ok then
            failed = failed + 1
            table.insert(errors, { name = file, error = err })
            io.write(RED .. "  ERROR loading " .. file .. ": " .. tostring(err) .. RESET .. "\n")
        end
    end

    print("")
    print(string.rep("-", 60))
    print(string.format(
        "%s%d passed%s, %s%d failed%s",
        GREEN, passed, RESET,
        failed > 0 and RED or GREEN, failed, RESET
    ))

    if #errors > 0 then
        print("")
        print(RED .. "Failures:" .. RESET)
        for i, e in ipairs(errors) do
            print(string.format("  %d) %s", i, e.name))
            print(string.format("     %s", e.error))
        end
    end

    print("")
    os.exit(failed > 0 and 1 or 0)
end

run()
