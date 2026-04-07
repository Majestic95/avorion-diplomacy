-- EDE Smoke Test — runs all pure logic modules in-game and reports via chat.
-- Attach to a station:
--   1. Target a station
--   2. /run Player().craft.selectedObject:addScript("entity/ede_smoke_test.lua")
--   3. Press F, click "EDE Smoke Test"
--
-- Remove when done:
--   /run Player().craft.selectedObject:removeScript("entity/ede_smoke_test.lua")

package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

function interactionPossible(playerIndex, option)
    return true
end

function initUI()
    ScriptUI():registerInteraction("EDE Smoke Test", "onRunTests", 9)
end

function onRunTests()
    if onClient() then
        invokeServerFunction("serverRunTests")
    end
end

function serverRunTests()
    if not onServer() then return end

    local player = Player(callingPlayer)
    if not player then return end

    local passed = 0
    local failed = 0
    local errors = {}

    local function msg(text)
        player:sendChatMessage("EDE", ChatMessageType.Normal, text)
    end

    local function check(name, fn)
        local ok, err = pcall(fn)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
            errors[#errors + 1] = name .. ": " .. tostring(err)
        end
    end

    msg("=== EDE Smoke Test Starting ===")

    -- Test 1: JSON module
    check("JSON encode/decode", function()
        local json = include("util/json")
        local data = { name = "test", value = 42, nested = { a = true } }
        local encoded = json.encode(data)
        local decoded = json.decode(encoded)
        assert(decoded.name == "test", "name mismatch")
        assert(decoded.value == 42, "value mismatch")
        assert(decoded.nested.a == true, "nested mismatch")
    end)

    -- Test 2: Persistence module
    check("Persistence save/load", function()
        local Persistence = include("util/persistence")
        local store = Server()
        Persistence.save(store, "smoke_test", { hello = "world", num = 123 })
        local loaded = Persistence.load(store, "smoke_test")
        assert(loaded.hello == "world", "string mismatch")
        assert(loaded.num == 123, "number mismatch")
        Persistence.delete(store, "smoke_test")
        local deleted = Persistence.load(store, "smoke_test")
        assert(deleted == nil, "delete failed")
    end)

    -- Test 3: Persistence bilateral
    check("Persistence bilateral", function()
        local Persistence = include("util/persistence")
        local store = Server()
        Persistence.saveBilateral(store, "smoke", 1, 2, { test = true })
        local loaded = Persistence.loadBilateral(store, "smoke", 2, 1)
        assert(loaded.test == true, "bilateral load failed")
        Persistence.deleteBilateral(store, "smoke", 1, 2)
    end)

    -- Test 4: Diplomatic States
    check("Diplomatic States", function()
        local States = include("diplomacy/states")
        assert(States.Type.TARIFF == "tariff", "tariff type mismatch")
        assert(States.Type.EMBARGO == "embargo", "embargo type mismatch")
        assert(States.Defaults[States.Type.TARIFF].rate == 0.15, "default rate mismatch")
    end)

    -- Test 5: Tariff math
    check("Tariff math", function()
        local Tariffs = include("economy/tariffs")
        local surcharge = Tariffs.calculateSurcharge(1000, 0.15)
        assert(surcharge == 150, "surcharge: expected 150, got " .. tostring(surcharge))
        local discounted = Tariffs.calculateDiscount(1000, 0.10)
        assert(discounted == 900, "discount: expected 900, got " .. tostring(discounted))
    end)

    -- Test 6: Power Score
    check("Power Score calculate", function()
        local PowerScore = include("economy/power_score")
        local score = PowerScore.calculate({
            ships = 10, stations = 4, money = 300000, sectors = 6,
        })
        assert(score == 293, "score: expected 293, got " .. tostring(score))
    end)

    check("Power Score enforcement", function()
        local PowerScore = include("economy/power_score")
        local can, _ = PowerScore.canEnforce(500, 1000, "tariff")
        assert(can == true, "should be able to enforce tariff at 0.5 ratio")
        local cant, _ = PowerScore.canEnforce(100, 1000, "tariff")
        assert(cant == false, "should NOT enforce tariff at 0.1 ratio")
    end)

    check("Power Score cost scaling", function()
        local PowerScore = include("economy/power_score")
        local cost_equal = PowerScore.enforcementCost(1000, 1000, 10000)
        assert(cost_equal == 10000, "equal cost: expected 10000, got " .. tostring(cost_equal))
        local cost_stronger = PowerScore.enforcementCost(500, 1000, 10000)
        assert(cost_stronger == 20000, "stronger cost: expected 20000, got " .. tostring(cost_stronger))
    end)

    -- Test 7: Territory cache
    check("Territory cache", function()
        local Territory = include("economy/territory")
        Territory.reset()
        Territory.setCount(999, 15)
        assert(Territory.getCount(999) == 15, "count mismatch")
        Territory.increment(999)
        assert(Territory.getCount(999) == 16, "increment mismatch")
        Territory.reset()
        assert(Territory.getCount(999) == 0, "reset failed")
    end)

    -- Test 8: Tariff Manager (full lifecycle)
    check("Tariff Manager declare/get/remove", function()
        local TariffManager = include("diplomacy/tariff_manager")
        local store = Server()
        -- Clean up any previous test data
        TariffManager.remove(store, 901, 902)

        local ok, err = TariffManager.declare(store, 901, 902, 500, 1000, 0.20, 1000)
        assert(ok == true, "declare failed: " .. tostring(err))

        local tariff = TariffManager.get(store, 901, 902)
        assert(tariff ~= nil, "get returned nil")
        assert(tariff.rate == 0.20, "rate mismatch: " .. tostring(tariff.rate))
        assert(tariff.active == true, "not active")

        local surcharge, rate = TariffManager.calculateSurcharge(store, 901, 902, 10000)
        assert(surcharge == 2000, "surcharge: expected 2000, got " .. tostring(surcharge))
        assert(rate == 0.20, "rate: expected 0.20, got " .. tostring(rate))

        TariffManager.remove(store, 901, 902)
        assert(TariffManager.get(store, 901, 902) == nil, "remove failed")
    end)

    -- Test 9: Agreement Manager (full lifecycle)
    check("Agreement Manager propose/accept/discount/cancel", function()
        local AgreementManager = include("diplomacy/agreement_manager")
        local store = Server()
        -- Clean up
        AgreementManager.cancel(store, 903, 904)

        local ok, err = AgreementManager.propose(store, 903, 904, 0.10, 0.15, 1000)
        assert(ok == true, "propose failed: " .. tostring(err))

        ok, err = AgreementManager.accept(store, 903, 904, 2000)
        assert(ok == true, "accept failed: " .. tostring(err))

        local agreement = AgreementManager.getActive(store, 903, 904)
        assert(agreement ~= nil, "active agreement is nil")
        assert(agreement.status == "active", "status mismatch")

        -- Faction 903 buying from 904 gets 15% (what 904 gives = target_discount)
        local discount = AgreementManager.getDiscount(store, 903, 904)
        assert(discount == 0.15, "discount for 903: expected 0.15, got " .. tostring(discount))

        -- Faction 904 buying from 903 gets 10% (what 903 gives = proposer_discount)
        local discount2 = AgreementManager.getDiscount(store, 904, 903)
        assert(discount2 == 0.10, "discount for 904: expected 0.10, got " .. tostring(discount2))

        AgreementManager.cancel(store, 903, 904)
        assert(AgreementManager.getActive(store, 903, 904) == nil, "cancel failed")
    end)

    -- Test 10: AI Behavior
    check("AI Behavior profiles", function()
        local AIBehavior = include("diplomacy/ai_behavior")
        local p = AIBehavior.getProfile("Corporate")
        assert(p.retaliation_chance == 0.70, "Corporate retaliation mismatch")
        assert(p.trade_affinity == 0.80, "Corporate trade_affinity mismatch")
    end)

    check("AI Behavior tariff response", function()
        local AIBehavior = include("diplomacy/ai_behavior")
        -- Corporate, roll 0.50, no agreement → should counter-tariff (0.50 < 0.70)
        local response, details = AIBehavior.respondToTariff("Corporate", 0.50, false)
        assert(response == "counter_tariff", "expected counter_tariff, got " .. tostring(response))
        assert(details.rate == 0.15, "expected rate 0.15")
    end)

    check("AI Behavior agreement proposal", function()
        local AIBehavior = include("diplomacy/ai_behavior")
        -- Corporate, high relations, very low roll → should propose
        local should, details = AIBehavior.shouldProposeAgreement("Corporate", 80000, 0.01)
        assert(should == true, "Corporate should propose with high relations and low roll")
        assert(details.discount > 0, "discount should be positive")
    end)

    -- Report results
    msg("=== Results: " .. passed .. " passed, " .. failed .. " failed ===")
    if failed > 0 then
        msg("FAILURES:")
        for _, e in ipairs(errors) do
            msg("  " .. e)
        end
    else
        msg("All modules working correctly in-game!")
    end
end

callable(nil, "serverRunTests")
