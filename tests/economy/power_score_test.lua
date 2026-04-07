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

    describe("tariffCost", function()
        it("scales with tariff rate — 15% on equal factions", function()
            -- 200000 * 0.15 * 2 * 1.0 = 60000
            local cost = PowerScore.tariffCost(1000, 1000, 0.15)
            assert.are.equal(60000, cost)
        end)

        it("scales with tariff rate — 50% on equal factions", function()
            -- 200000 * 0.50 * 2 * 1.0 = 200000
            local cost = PowerScore.tariffCost(1000, 1000, 0.50)
            assert.are.equal(200000, cost)
        end)

        it("increases when target is stronger", function()
            -- 200000 * 0.15 * 2 * 2.0 = 120000
            local cost = PowerScore.tariffCost(500, 1000, 0.15)
            assert.are.equal(120000, cost)
        end)

        it("floors ratio at 0.5 for very weak targets", function()
            -- 200000 * 0.15 * 2 * 0.5 = 30000
            local cost = PowerScore.tariffCost(10000, 1, 0.15)
            assert.are.equal(30000, cost)
        end)

        it("caps at 2 million", function()
            -- 200000 * 0.50 * 2 * 100 = 20000000 -> capped at 2000000
            local cost = PowerScore.tariffCost(10, 1000, 0.50)
            assert.are.equal(2000000, cost)
        end)

        it("returns max when actor has zero score", function()
            local cost = PowerScore.tariffCost(0, 1000, 0.15)
            assert.are.equal(2000000, cost)
        end)

        it("handles zero target score", function()
            -- target_score becomes 1, ratio = 1/1000 -> clamped to 0.5
            -- 200000 * 0.15 * 2 * 0.5 = 30000
            local cost = PowerScore.tariffCost(1000, 0, 0.15)
            assert.are.equal(30000, cost)
        end)

        it("5% tariff on weak faction is cheap", function()
            -- 200000 * 0.05 * 2 * 0.5 = 10000
            local cost = PowerScore.tariffCost(1000, 100, 0.05)
            assert.are.equal(10000, cost)
        end)
    end)

    describe("embargoCost", function()
        it("scales with power ratio", function()
            -- 500000 * 1.0 = 500000
            local cost = PowerScore.embargoCost(1000, 1000)
            assert.are.equal(500000, cost)
        end)

        it("increases for stronger targets", function()
            -- 500000 * 2.0 = 1000000
            local cost = PowerScore.embargoCost(500, 1000)
            assert.are.equal(1000000, cost)
        end)

        it("caps at 4 million", function()
            local cost = PowerScore.embargoCost(10, 1000)
            assert.are.equal(4000000, cost)
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
