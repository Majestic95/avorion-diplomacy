-- Test: Tariff Manager
-- Run with: bash tools/test.sh tests/diplomacy/tariff_manager_test.lua

dofile("tests/mocks/avorion.lua")

describe("TariffManager", function()
    local TariffManager
    local store

    before_each(function()
        _resetMocks()
        TariffManager = include("diplomacy/tariff_manager")
        store = Galaxy()
    end)

    describe("clampRate", function()
        it("returns default rate for nil", function()
            assert.are.equal(0.15, TariffManager.clampRate(nil))
        end)

        it("clamps rate below minimum", function()
            assert.are.equal(0.01, TariffManager.clampRate(0.001))
        end)

        it("clamps rate above maximum", function()
            assert.are.equal(0.50, TariffManager.clampRate(0.75))
        end)

        it("passes through valid rate", function()
            assert.are.equal(0.25, TariffManager.clampRate(0.25))
        end)
    end)

    describe("declare", function()
        it("succeeds when enforcement threshold is met", function()
            -- Score 500 vs 1000, ratio 0.50 >= 0.30 threshold
            local ok, err = TariffManager.declare(store, 1, 2, 500, 1000, 0.15, 1000)
            assert.is_true(ok)
            assert.is_nil(err)
        end)

        it("creates a retrievable tariff record", function()
            TariffManager.declare(store, 1, 2, 500, 1000, 0.20, 1000)
            local tariff = TariffManager.get(store, 1, 2)
            assert.is_not_nil(tariff)
            assert.are.equal(1, tariff.imposer)
            assert.are.equal(2, tariff.target)
            assert.are.equal(0.20, tariff.rate)
            assert.is_true(tariff.active)
            assert.are.equal(1000, tariff.declared_at)
            assert.are.equal(0, tariff.total_revenue)
        end)

        it("fails when enforcement threshold is not met", function()
            -- Score 100 vs 1000, ratio 0.10 < 0.30
            local ok, err = TariffManager.declare(store, 1, 2, 100, 1000, 0.15, 1000)
            assert.is_false(ok)
            assert.are.equal("Insufficient power to enforce tariff", err)
        end)

        it("fails when tariffing yourself", function()
            local ok, err = TariffManager.declare(store, 1, 1, 1000, 1000, 0.15, 1000)
            assert.is_false(ok)
            assert.are.equal("Cannot impose tariff on yourself", err)
        end)

        it("fails when duplicate tariff exists", function()
            TariffManager.declare(store, 1, 2, 500, 1000, 0.15, 1000)
            local ok, err = TariffManager.declare(store, 1, 2, 500, 1000, 0.20, 2000)
            assert.is_false(ok)
            assert.are.equal("Tariff already active against this faction", err)
        end)

        it("clamps rate to valid range", function()
            TariffManager.declare(store, 1, 2, 500, 1000, 0.99, 1000)
            local tariff = TariffManager.get(store, 1, 2)
            assert.are.equal(0.50, tariff.rate)
        end)

        it("adds to master index", function()
            TariffManager.declare(store, 1, 2, 500, 1000, 0.15, 1000)
            local active = TariffManager.getAllActive(store)
            assert.are.equal(1, #active)
            assert.are.equal(1, active[1].imposer)
            assert.are.equal(2, active[1].target)
        end)

        it("is directional — A→B and B→A are separate", function()
            TariffManager.declare(store, 1, 2, 500, 1000, 0.15, 1000)
            TariffManager.declare(store, 2, 1, 500, 500, 0.10, 1000)
            local t12 = TariffManager.get(store, 1, 2)
            local t21 = TariffManager.get(store, 2, 1)
            assert.are.equal(0.15, t12.rate)
            assert.are.equal(0.10, t21.rate)
        end)
    end)

    describe("getEffectiveRate", function()
        it("returns 0 when no tariffs exist", function()
            local rate, tariff = TariffManager.getEffectiveRate(store, 1, 2)
            assert.are.equal(0, rate)
            assert.is_nil(tariff)
        end)

        it("returns the rate when one direction has a tariff", function()
            TariffManager.declare(store, 1, 2, 500, 1000, 0.20, 1000)
            local rate, _ = TariffManager.getEffectiveRate(store, 1, 2)
            assert.are.equal(0.20, rate)
        end)

        it("returns the higher rate when both directions have tariffs", function()
            TariffManager.declare(store, 1, 2, 500, 1000, 0.15, 1000)
            TariffManager.declare(store, 2, 1, 500, 500, 0.25, 1000)
            local rate, _ = TariffManager.getEffectiveRate(store, 1, 2)
            assert.are.equal(0.25, rate)
        end)
    end)

    describe("calculateSurcharge", function()
        it("returns 0 when no tariff exists", function()
            local surcharge, rate = TariffManager.calculateSurcharge(store, 1, 2, 10000)
            assert.are.equal(0, surcharge)
            assert.are.equal(0, rate)
        end)

        it("calculates correct surcharge with active tariff", function()
            TariffManager.declare(store, 1, 2, 500, 1000, 0.15, 1000)
            local surcharge, rate = TariffManager.calculateSurcharge(store, 1, 2, 10000)
            assert.are.equal(1500, surcharge)
            assert.are.equal(0.15, rate)
        end)
    end)

    describe("remove", function()
        it("removes an existing tariff", function()
            TariffManager.declare(store, 1, 2, 500, 1000, 0.15, 1000)
            local ok = TariffManager.remove(store, 1, 2)
            assert.is_true(ok)
            assert.is_nil(TariffManager.get(store, 1, 2))
        end)

        it("returns false for non-existent tariff", function()
            assert.is_false(TariffManager.remove(store, 1, 2))
        end)

        it("removes from master index", function()
            TariffManager.declare(store, 1, 2, 500, 1000, 0.15, 1000)
            TariffManager.remove(store, 1, 2)
            local active = TariffManager.getAllActive(store)
            assert.are.equal(0, #active)
        end)

        it("does not affect other tariffs", function()
            TariffManager.declare(store, 1, 2, 500, 1000, 0.15, 1000)
            TariffManager.declare(store, 3, 4, 500, 1000, 0.20, 1000)
            TariffManager.remove(store, 1, 2)
            assert.is_not_nil(TariffManager.get(store, 3, 4))
            assert.are.equal(1, #TariffManager.getAllActive(store))
        end)
    end)

    describe("processPaymentCycle", function()
        it("deducts cost when imposer can pay", function()
            TariffManager.declare(store, 1, 2, 500, 500, 0.15, 1000)
            local active, cost = TariffManager.processPaymentCycle(
                store, 1, 2, 50000, 500, 500, 2000
            )
            assert.is_true(active)
            assert.is_true(cost > 0)
        end)

        it("enters grace period on first missed payment", function()
            TariffManager.declare(store, 1, 2, 500, 500, 0.15, 1000)
            local active, cost = TariffManager.processPaymentCycle(
                store, 1, 2, 0, 500, 500, 2000
            )
            assert.is_true(active) -- still in grace period
            assert.are.equal(0, cost) -- no charge
        end)

        it("lapses tariff after grace period expires", function()
            TariffManager.declare(store, 1, 2, 500, 500, 0.15, 1000)
            -- First missed payment (grace)
            TariffManager.processPaymentCycle(store, 1, 2, 0, 500, 500, 2000)
            -- Second missed payment (exceeds 1 grace day)
            local active, cost = TariffManager.processPaymentCycle(
                store, 1, 2, 0, 500, 500, 3000
            )
            assert.is_false(active)
            assert.are.equal(0, cost)
            assert.is_nil(TariffManager.get(store, 1, 2))
        end)

        it("resets missed payments on successful payment", function()
            TariffManager.declare(store, 1, 2, 500, 500, 0.15, 1000)
            -- Miss one payment
            TariffManager.processPaymentCycle(store, 1, 2, 0, 500, 500, 2000)
            -- Pay successfully
            TariffManager.processPaymentCycle(store, 1, 2, 50000, 500, 500, 3000)
            local tariff = TariffManager.get(store, 1, 2)
            assert.are.equal(0, tariff.missed_payments)
        end)

        it("returns false for non-existent tariff", function()
            local active, cost = TariffManager.processPaymentCycle(
                store, 1, 2, 50000, 500, 500, 1000
            )
            assert.is_false(active)
            assert.are.equal(0, cost)
        end)
    end)

    describe("recordRevenue", function()
        it("accumulates revenue on tariff record", function()
            TariffManager.declare(store, 1, 2, 500, 1000, 0.15, 1000)
            TariffManager.recordRevenue(store, 1, 2, 500)
            TariffManager.recordRevenue(store, 1, 2, 300)
            local tariff = TariffManager.get(store, 1, 2)
            assert.are.equal(800, tariff.total_revenue)
        end)

        it("does nothing for non-existent tariff", function()
            TariffManager.recordRevenue(store, 1, 2, 500)
            -- No error thrown
        end)
    end)

    describe("getAllActive", function()
        it("returns empty when no tariffs exist", function()
            assert.are.equal(0, #TariffManager.getAllActive(store))
        end)

        it("returns all active tariff pairs", function()
            TariffManager.declare(store, 1, 2, 500, 1000, 0.15, 1000)
            TariffManager.declare(store, 3, 4, 500, 1000, 0.20, 1000)
            TariffManager.declare(store, 5, 6, 500, 1000, 0.10, 1000)
            assert.are.equal(3, #TariffManager.getAllActive(store))
        end)
    end)
end)
