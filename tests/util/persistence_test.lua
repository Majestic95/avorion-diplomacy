-- Test: Persistence Layer
-- Run with: bash tools/test.sh tests/util/persistence_test.lua

dofile("tests/mocks/avorion.lua")

describe("Persistence", function()
    local Persistence
    local store

    before_each(function()
        _resetMocks()
        Persistence = include("util/persistence")
        -- Use Galaxy() mock as a store (has setValue/getValue from mock)
        store = Galaxy()
    end)

    describe("key", function()
        it("prefixes keys with ede_", function()
            assert.are.equal("ede_test", Persistence.key("test"))
        end)

        it("handles empty string", function()
            assert.are.equal("ede_", Persistence.key(""))
        end)
    end)

    describe("save / load", function()
        it("stores and retrieves a string", function()
            Persistence.save(store, "name", "hello")
            assert.are.equal("hello", Persistence.load(store, "name"))
        end)

        it("stores and retrieves a number", function()
            Persistence.save(store, "count", 42)
            assert.are.equal(42, Persistence.load(store, "count"))
        end)

        it("stores and retrieves a boolean", function()
            Persistence.save(store, "flag", true)
            assert.are.equal(true, Persistence.load(store, "flag"))
        end)

        it("stores and retrieves a table via JSON", function()
            local data = { type = "tariff", rate = 0.15, active = true }
            Persistence.save(store, "state", data)
            local loaded = Persistence.load(store, "state")
            assert.are.equal("tariff", loaded.type)
            assert.are.equal(0.15, loaded.rate)
            assert.are.equal(true, loaded.active)
        end)

        it("stores and retrieves an array via JSON", function()
            local data = { 10, 20, 30 }
            Persistence.save(store, "arr", data)
            local loaded = Persistence.load(store, "arr")
            assert.are.equal(10, loaded[1])
            assert.are.equal(20, loaded[2])
            assert.are.equal(30, loaded[3])
        end)

        it("returns nil for missing keys", function()
            assert.is_nil(Persistence.load(store, "nonexistent"))
        end)

        it("returns plain string if not JSON-like", function()
            Persistence.save(store, "plain", "just a string")
            assert.are.equal("just a string", Persistence.load(store, "plain"))
        end)
    end)

    describe("delete", function()
        it("removes a stored value", function()
            Persistence.save(store, "temp", "data")
            Persistence.delete(store, "temp")
            assert.is_nil(Persistence.load(store, "temp"))
        end)
    end)

    describe("saveBilateral / loadBilateral", function()
        it("stores bilateral state between two factions", function()
            local data = { type = "tariff", rate = 0.15 }
            Persistence.saveBilateral(store, "tariff", 1, 2, data)
            local loaded = Persistence.loadBilateral(store, "tariff", 1, 2)
            assert.are.equal("tariff", loaded.type)
            assert.are.equal(0.15, loaded.rate)
        end)

        it("is order-independent (1,2 same as 2,1)", function()
            Persistence.saveBilateral(store, "tariff", 5, 3, { rate = 0.20 })
            local loaded = Persistence.loadBilateral(store, "tariff", 3, 5)
            assert.are.equal(0.20, loaded.rate)
        end)

        it("returns nil for missing bilateral state", function()
            assert.is_nil(Persistence.loadBilateral(store, "tariff", 1, 2))
        end)
    end)

    describe("deleteBilateral", function()
        it("removes bilateral state", function()
            Persistence.saveBilateral(store, "agreement", 1, 2, { discount = 0.10 })
            Persistence.deleteBilateral(store, "agreement", 1, 2)
            assert.is_nil(Persistence.loadBilateral(store, "agreement", 1, 2))
        end)

        it("is order-independent for deletion", function()
            Persistence.saveBilateral(store, "agreement", 3, 7, { discount = 0.10 })
            Persistence.deleteBilateral(store, "agreement", 7, 3)
            assert.is_nil(Persistence.loadBilateral(store, "agreement", 3, 7))
        end)
    end)
end)
