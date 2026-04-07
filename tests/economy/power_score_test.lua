-- Test: Power Projection Score Calculator
-- Run with: bash tools/test.sh tests/economy/power_score_test.lua

dofile("tests/mocks/avorion.lua")

describe("PowerScore", function()
    local PowerScore

    before_each(function()
        _resetMocks()
        PowerScore = include("economy/power_score")
    end)

    describe("calculate", function()
        it("returns 0 for empty data", function()
            assert.are.equal(0, PowerScore.calculate({}))
        end)

        it("returns 0 for all-zero data", function()
            assert.are.equal(0, PowerScore.calculate({ ships = 0, stations = 0, money = 0, sectors = 0 }))
        end)

        it("scores ships correctly", function()
            local score = PowerScore.calculate({ ships = 5, stations = 0, money = 0, sectors = 0 })
            assert.are.equal(50, score) -- 5 * 10
        end)

        it("scores stations correctly", function()
            local score = PowerScore.calculate({ ships = 0, stations = 3, money = 0, sectors = 0 })
            assert.are.equal(75, score) -- 3 * 25
        end)

        it("scores money correctly with divisor", function()
            local score = PowerScore.calculate({ ships = 0, stations = 0, money = 500000, sectors = 0 })
            assert.are.equal(5, score) -- floor(500000/100000) * 1 = 5
        end)

        it("floors money to nearest 100K", function()
            local score = PowerScore.calculate({ ships = 0, stations = 0, money = 199999, sectors = 0 })
            assert.are.equal(1, score) -- floor(199999/100000) = 1
        end)

        it("scores sectors correctly", function()
            local score = PowerScore.calculate({ ships = 0, stations = 0, money = 0, sectors = 8 })
            assert.are.equal(120, score) -- 8 * 15
        end)

        it("combines all inputs", function()
            local score = PowerScore.calculate({
                ships = 10,    -- 100
                stations = 4,  -- 100
                money = 300000, -- 3
                sectors = 6,   -- 90
            })
            assert.are.equal(293, score) -- 100 + 100 + 3 + 90
        end)

        it("applies archetype bonus for Militaristic", function()
            local score = PowerScore.calculate({
                ships = 0, stations = 0, money = 0, sectors = 0,
                archetype = "Militaristic",
            })
            assert.are.equal(100, score)
        end)

        it("applies archetype bonus for Corporate", function()
            local score = PowerScore.calculate({
                ships = 0, stations = 0, money = 0, sectors = 0,
                archetype = "Corporate",
            })
            assert.are.equal(75, score)
        end)

        it("ignores unknown archetype", function()
            local score = PowerScore.calculate({
                ships = 0, stations = 0, money = 0, sectors = 0,
                archetype = "NonexistentType",
            })
            assert.are.equal(0, score)
        end)

        it("ignores nil archetype", function()
            local score = PowerScore.calculate({
                ships = 5, stations = 0, money = 0, sectors = 0,
                archetype = nil,
            })
            assert.are.equal(50, score)
        end)

        it("clamps negative inputs to zero", function()
            local score = PowerScore.calculate({ ships = -5, stations = -2, money = -100000, sectors = -3 })
            assert.are.equal(0, score)
        end)

        it("handles missing fields gracefully", function()
            local score = PowerScore.calculate({ ships = 10 })
            assert.are.equal(100, score)
        end)

        it("accepts custom weights", function()
            local custom = {
                SHIP = 20,
                STATION = 50,
                MONEY = 2,
                SECTOR = 30,
                MONEY_DIVISOR = 100000,
            }
            local score = PowerScore.calculate({ ships = 5, stations = 2, money = 200000, sectors = 3 }, custom)
            assert.are.equal(294, score) -- 100 + 100 + 4 + 90
        end)
    end)

    describe("canEnforce", function()
        it("allows tariff when ratio meets threshold", function()
            local can, _ = PowerScore.canEnforce(300, 1000, "tariff") -- 0.3 >= 0.3
            assert.is_true(can)
        end)

        it("denies tariff when ratio is below threshold", function()
            local can, _ = PowerScore.canEnforce(299, 1000, "tariff") -- 0.299 < 0.3
            assert.is_false(can)
        end)

        it("allows embargo when ratio meets threshold", function()
            local can, _ = PowerScore.canEnforce(500, 1000, "embargo") -- 0.5 >= 0.5
            assert.is_true(can)
        end)

        it("denies embargo when ratio is below threshold", function()
            local can, _ = PowerScore.canEnforce(499, 1000, "embargo") -- 0.499 < 0.5
            assert.is_false(can)
        end)

        it("allows enforcement against zero-score target", function()
            local can, ratio = PowerScore.canEnforce(100, 0, "tariff")
            assert.is_true(can)
            assert.are.equal(1.0, ratio)
        end)

        it("denies enforcement with zero actor score", function()
            local can, ratio = PowerScore.canEnforce(0, 100, "tariff")
            assert.is_false(can)
            assert.are.equal(0.0, ratio)
        end)

        it("returns correct ratio", function()
            local can, ratio = PowerScore.canEnforce(750, 1000, "tariff")
            assert.is_true(can)
            assert.are.equal(0.75, ratio)
        end)

        it("denies unknown action types", function()
            local can, _ = PowerScore.canEnforce(1000, 100, "invalid_action")
            assert.is_false(can)
        end)

        it("handles case insensitive action types", function()
            local can, _ = PowerScore.canEnforce(500, 1000, "TARIFF")
            assert.is_true(can)
        end)
    end)

    describe("enforcementCost", function()
        it("returns base cost when scores are equal", function()
            local cost = PowerScore.enforcementCost(1000, 1000, 10000)
            assert.are.equal(10000, cost)
        end)

        it("increases cost when target is stronger", function()
            local cost = PowerScore.enforcementCost(500, 1000, 10000) -- ratio 2.0
            assert.are.equal(20000, cost)
        end)

        it("decreases cost when target is weaker but floors at 0.5x", function()
            local cost = PowerScore.enforcementCost(10000, 100, 10000) -- ratio 0.01 -> clamped to 0.5
            assert.are.equal(5000, cost)
        end)

        it("floors at half base cost for very weak targets", function()
            local cost = PowerScore.enforcementCost(5000, 1, 10000)
            assert.are.equal(5000, cost)
        end)

        it("returns high cost when actor has zero score", function()
            local cost = PowerScore.enforcementCost(0, 1000, 10000)
            assert.are.equal(100000, cost) -- 10x penalty
        end)

        it("returns half base cost when target has zero score", function()
            local cost = PowerScore.enforcementCost(1000, 0, 10000)
            assert.are.equal(5000, cost)
        end)

        it("rounds to nearest integer", function()
            local cost = PowerScore.enforcementCost(700, 1000, 10000) -- ratio ~1.4286
            assert.are.equal(14286, cost)
        end)
    end)

    describe("compare", function()
        it("returns full comparison summary", function()
            local actor = { ships = 20, stations = 5, money = 500000, sectors = 10 }
            local target = { ships = 10, stations = 3, money = 200000, sectors = 5 }

            local result = PowerScore.compare(actor, target)

            assert.is_not_nil(result.actor_score)
            assert.is_not_nil(result.target_score)
            assert.is_true(result.actor_score > result.target_score)
            assert.is_true(result.can_tariff)
            assert.is_true(result.can_embargo)
            assert.is_number(result.tariff_cost)
            assert.is_number(result.embargo_cost)
        end)

        it("correctly identifies when tariff is allowed but embargo is not", function()
            -- Actor score ~35% of target → tariff yes (30%), embargo no (50%)
            local actor = { ships = 5, stations = 1, money = 100000, sectors = 2 }  -- 106
            local target = { ships = 15, stations = 5, money = 500000, sectors = 10 } -- 430

            local result = PowerScore.compare(actor, target)

            -- ratio should be roughly 0.24 — let's check
            -- Actually compute: actor = 50+25+1+30 = 106, target = 150+125+5+150 = 430
            -- ratio = 106/430 = 0.246 — below 0.30, so no tariff either
            assert.is_false(result.can_tariff)
            assert.is_false(result.can_embargo)
        end)

        it("embargo costs more than tariff for same matchup", function()
            local actor = { ships = 20, stations = 5, money = 500000, sectors = 10 }
            local target = { ships = 10, stations = 3, money = 200000, sectors = 5 }

            local result = PowerScore.compare(actor, target)

            assert.is_true(result.embargo_cost > result.tariff_cost)
        end)
    end)
end)
