-- Test: AI Faction Diplomatic Behavior
-- Run with: bash tools/test.sh tests/diplomacy/ai_behavior_test.lua

dofile("tests/mocks/avorion.lua")

describe("AIBehavior", function()
    local AIBehavior

    before_each(function()
        _resetMocks()
        AIBehavior = include("diplomacy/ai_behavior")
    end)

    describe("getProfile", function()
        it("returns profile for known archetype", function()
            local p = AIBehavior.getProfile("Corporate")
            assert.is_not_nil(p)
            assert.are.equal(0.70, p.retaliation_chance)
            assert.are.equal(0.80, p.trade_affinity)
        end)

        it("returns Vanilla profile for unknown archetype", function()
            local p = AIBehavior.getProfile("NonexistentType")
            assert.are.equal(AIBehavior.Profiles.Vanilla.retaliation_chance, p.retaliation_chance)
        end)

        it("has profiles for all standard archetypes", function()
            local archetypes = {
                "Vanilla", "Traditional", "Independent", "Militaristic",
                "Religious", "Corporate", "Alliance", "Sect",
            }
            for _, a in ipairs(archetypes) do
                local p = AIBehavior.getProfile(a)
                assert.is_not_nil(p, "Missing profile for " .. a)
                assert.is_number(p.retaliation_chance)
                assert.is_number(p.escalation_speed)
                assert.is_number(p.forgiveness)
                assert.is_number(p.trade_affinity)
            end
        end)
    end)

    describe("respondToTariff", function()
        it("breaks agreement if one exists", function()
            local response, details = AIBehavior.respondToTariff("Corporate", 0.5, true)
            assert.are.equal(AIBehavior.Response.BREAK_AGREEMENT, response)
            assert.are.equal("retaliatory_break", details.reason)
        end)

        it("counter-tariffs when roll is below retaliation chance", function()
            -- Corporate retaliation_chance = 0.70, roll 0.50 < 0.70
            local response, details = AIBehavior.respondToTariff("Corporate", 0.50, false)
            assert.are.equal(AIBehavior.Response.COUNTER_TARIFF, response)
            assert.are.equal(0.15, details.rate)
        end)

        it("drops relations when roll exceeds retaliation chance", function()
            -- Corporate retaliation_chance = 0.70, roll 0.80 > 0.70
            local response, details = AIBehavior.respondToTariff("Corporate", 0.80, false)
            assert.are.equal(AIBehavior.Response.RELATION_DROP, response)
            assert.is_number(details.amount)
            assert.is_true(details.amount < 0)
        end)

        it("Militaristic factions almost always retaliate", function()
            -- Militaristic retaliation_chance = 0.95
            local response, _ = AIBehavior.respondToTariff("Militaristic", 0.90, false)
            assert.are.equal(AIBehavior.Response.COUNTER_TARIFF, response)
        end)

        it("Militaristic relation drops are severe", function()
            -- escalation_speed = 3, so drop = -10000 * 3 = -30000
            local response, details = AIBehavior.respondToTariff("Militaristic", 0.99, false)
            assert.are.equal(AIBehavior.Response.RELATION_DROP, response)
            assert.are.equal(-30000, details.amount)
        end)

        it("Independent factions are less likely to retaliate", function()
            -- Independent retaliation_chance = 0.50, roll 0.60 > 0.50
            local response, _ = AIBehavior.respondToTariff("Independent", 0.60, false)
            assert.are.equal(AIBehavior.Response.RELATION_DROP, response)
        end)
    end)

    describe("respondToEmbargo", function()
        it("Militaristic factions may escalate to near-war", function()
            local response, details = AIBehavior.respondToEmbargo("Militaristic", 0.30)
            assert.are.equal(AIBehavior.Response.RELATION_DROP, response)
            assert.are.equal(-80000, details.amount)
        end)

        it("non-Militaristic factions counter-tariff at punitive rate", function()
            local response, details = AIBehavior.respondToEmbargo("Corporate", 0.50)
            assert.are.equal(AIBehavior.Response.COUNTER_TARIFF, response)
            assert.are.equal(0.30, details.rate)
        end)

        it("embargo always causes relation drop in details", function()
            local _, details = AIBehavior.respondToEmbargo("Corporate", 0.50)
            assert.is_not_nil(details.relation_drop)
            assert.is_true(details.relation_drop < 0)
        end)

        it("Militaristic with high roll still counter-tariffs", function()
            local response, details = AIBehavior.respondToEmbargo("Militaristic", 0.80)
            assert.are.equal(AIBehavior.Response.COUNTER_TARIFF, response)
            assert.are.equal(0.30, details.rate)
        end)
    end)

    describe("shouldProposeAgreement", function()
        it("never proposes with negative relations", function()
            local should, _ = AIBehavior.shouldProposeAgreement("Corporate", -5000, 0.01)
            assert.is_false(should)
        end)

        it("never proposes with low positive relations", function()
            local should, _ = AIBehavior.shouldProposeAgreement("Corporate", 5000, 0.01)
            assert.is_false(should)
        end)

        it("Corporate with high relations and low roll proposes", function()
            -- relation 80000, trade_affinity 0.80, factor 0.8
            -- chance = 0.80 * 0.8 * 0.10 = 0.064
            local should, details = AIBehavior.shouldProposeAgreement("Corporate", 80000, 0.01)
            assert.is_true(should)
            assert.is_not_nil(details)
            assert.is_number(details.discount)
            assert.is_true(details.discount > 0)
        end)

        it("Militaristic rarely proposes even with good relations", function()
            -- trade_affinity 0.20, even with max relations
            -- chance = 0.20 * 1.0 * 0.10 = 0.02
            local should, _ = AIBehavior.shouldProposeAgreement("Militaristic", 100000, 0.05)
            assert.is_false(should) -- 0.05 > 0.02
        end)

        it("returns nil details when not proposing", function()
            local should, details = AIBehavior.shouldProposeAgreement("Corporate", 80000, 0.99)
            assert.is_false(should)
            assert.is_nil(details)
        end)
    end)

    describe("shouldImposeTariff", function()
        it("never imposes with positive relations", function()
            local should, _ = AIBehavior.shouldImposeTariff("Militaristic", 5000, 0.01)
            assert.is_false(should)
        end)

        it("never imposes with mildly negative relations", function()
            local should, _ = AIBehavior.shouldImposeTariff("Militaristic", -5000, 0.01)
            assert.is_false(should)
        end)

        it("Militaristic with bad relations and low roll imposes", function()
            -- relation -80000, hostility 0.8, escalation 3
            -- chance = 0.8 * 0.05 * 3 = 0.12
            local should, details = AIBehavior.shouldImposeTariff("Militaristic", -80000, 0.05)
            assert.is_true(should)
            assert.is_not_nil(details)
            assert.is_number(details.rate)
            assert.is_true(details.rate >= 0.10)
        end)

        it("Corporate with bad relations is less aggressive", function()
            -- escalation_speed 1, so chance is lower
            -- relation -50000, hostility 0.5
            -- chance = 0.5 * 0.05 * 1 = 0.025
            local should, _ = AIBehavior.shouldImposeTariff("Corporate", -50000, 0.05)
            assert.is_false(should) -- 0.05 > 0.025
        end)

        it("returns nil details when not imposing", function()
            local should, details = AIBehavior.shouldImposeTariff("Corporate", -80000, 0.99)
            assert.is_false(should)
            assert.is_nil(details)
        end)
    end)
end)
