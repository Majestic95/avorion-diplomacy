-- Test: Diplomatic States module
-- Run with: lua5.1 tools/testrunner.lua tests/diplomacy/states_test.lua

dofile("tests/mocks/avorion.lua")

describe("Diplomatic States", function()
    local States

    before_each(function()
        _resetMocks()
        States = include("diplomacy/states")
    end)

    describe("Type enum", function()
        it("defines all expected state types", function()
            assert.is_not_nil(States.Type.NONE)
            assert.is_not_nil(States.Type.TRADE_AGREEMENT)
            assert.is_not_nil(States.Type.TARIFF)
            assert.is_not_nil(States.Type.EMBARGO)
            assert.is_not_nil(States.Type.SANCTIONS)
            assert.is_not_nil(States.Type.BLOCKADE)
            assert.is_not_nil(States.Type.NON_AGGRESSION)
        end)

        it("uses unique string values", function()
            local seen = {}
            for _, v in pairs(States.Type) do
                assert.is_nil(seen[v], "duplicate state type value: " .. v)
                seen[v] = true
            end
        end)
    end)

    describe("Defaults", function()
        it("provides default tariff rate", function()
            local tariff_defaults = States.Defaults[States.Type.TARIFF]
            assert.is_not_nil(tariff_defaults)
            assert.is_number(tariff_defaults.rate)
            assert.is_true(tariff_defaults.rate > 0 and tariff_defaults.rate <= 1)
        end)

        it("provides default trade agreement discount", function()
            local ta_defaults = States.Defaults[States.Type.TRADE_AGREEMENT]
            assert.is_not_nil(ta_defaults)
            assert.is_number(ta_defaults.discount)
            assert.is_true(ta_defaults.discount > 0 and ta_defaults.discount <= 1)
        end)
    end)
end)
