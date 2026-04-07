-- Test: Territory Cache
-- Run with: bash tools/test.sh tests/economy/territory_test.lua

dofile("tests/mocks/avorion.lua")

describe("Territory", function()
    local Territory

    before_each(function()
        _resetMocks()
        Territory = include("economy/territory")
        Territory.reset()
    end)

    describe("setCount / getCount", function()
        it("returns 0 for unknown faction", function()
            assert.are.equal(0, Territory.getCount(999))
        end)

        it("stores and retrieves a count", function()
            Territory.setCount(1, 15)
            assert.are.equal(15, Territory.getCount(1))
        end)

        it("overwrites previous count", function()
            Territory.setCount(1, 15)
            Territory.setCount(1, 20)
            assert.are.equal(20, Territory.getCount(1))
        end)

        it("clamps negative count to zero", function()
            Territory.setCount(1, -5)
            assert.are.equal(0, Territory.getCount(1))
        end)

        it("handles nil count as zero", function()
            Territory.setCount(1, nil)
            assert.are.equal(0, Territory.getCount(1))
        end)
    end)

    describe("increment", function()
        it("increments from zero", function()
            Territory.increment(1)
            assert.are.equal(1, Territory.getCount(1))
        end)

        it("increments existing count", function()
            Territory.setCount(1, 5)
            Territory.increment(1)
            assert.are.equal(6, Territory.getCount(1))
        end)

        it("increments multiple factions independently", function()
            Territory.increment(1)
            Territory.increment(1)
            Territory.increment(2)
            assert.are.equal(2, Territory.getCount(1))
            assert.are.equal(1, Territory.getCount(2))
        end)
    end)

    describe("getAll", function()
        it("returns empty table when no data", function()
            local all = Territory.getAll()
            local count = 0
            for _ in pairs(all) do count = count + 1 end
            assert.are.equal(0, count)
        end)

        it("returns copy of all faction counts", function()
            Territory.setCount(1, 10)
            Territory.setCount(2, 20)
            local all = Territory.getAll()
            assert.are.equal(10, all[1])
            assert.are.equal(20, all[2])
        end)

        it("returns a copy, not a reference", function()
            Territory.setCount(1, 10)
            local all = Territory.getAll()
            all[1] = 999
            assert.are.equal(10, Territory.getCount(1))
        end)
    end)

    describe("reset", function()
        it("clears all data", function()
            Territory.setCount(1, 10)
            Territory.setTimestamp(5000)
            Territory.reset()
            assert.are.equal(0, Territory.getCount(1))
            assert.are.equal(0, Territory.getTimestamp())
        end)
    end)

    describe("timestamp and staleness", function()
        it("starts with zero timestamp", function()
            assert.are.equal(0, Territory.getTimestamp())
        end)

        it("stores and retrieves timestamp", function()
            Territory.setTimestamp(1000)
            assert.are.equal(1000, Territory.getTimestamp())
        end)

        it("is stale when timestamp is zero", function()
            assert.is_true(Territory.isStale(5000, 3600))
        end)

        it("is not stale within max age", function()
            Territory.setTimestamp(1000)
            assert.is_false(Territory.isStale(2000, 3600))
        end)

        it("is stale when past max age", function()
            Territory.setTimestamp(1000)
            assert.is_true(Territory.isStale(5000, 3600))
        end)

        it("is stale at exact max age boundary", function()
            Territory.setTimestamp(1000)
            assert.is_true(Territory.isStale(4600, 3600))
        end)
    end)

    describe("buildScanGrid", function()
        it("generates grid coordinates around center", function()
            local coords = Territory.buildScanGrid(0, 0, 20, 10)
            assert.is_true(#coords > 0)
        end)

        it("generates correct count for small grid", function()
            -- center 0,0, radius 10, step 10
            -- x: -10, 0, 10 (3 values)
            -- y: -10, 0, 10 (3 values)
            -- total: 3 * 3 = 9
            local coords = Territory.buildScanGrid(0, 0, 10, 10)
            assert.are.equal(9, #coords)
        end)

        it("includes center coordinate", function()
            local coords = Territory.buildScanGrid(100, 200, 10, 10)
            local found = false
            for _, c in ipairs(coords) do
                if c.x == 100 and c.y == 200 then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("defaults step to 10", function()
            local coords = Territory.buildScanGrid(0, 0, 10)
            assert.are.equal(9, #coords)
        end)
    end)
end)
