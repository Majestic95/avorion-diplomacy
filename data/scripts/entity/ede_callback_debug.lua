-- EDE Callback Debug — tests MULTIPLE callback approaches to find what works.
-- Attach to a trading station:
--   /run Player().craft.selectedObject:addScriptOnce("entity/ede_callback_debug.lua")

package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

function initialize()
    if onServer() then
        print("[EDE CB DEBUG] initialize() running on server")

        -- Try registerCallback for trade events
        Entity():registerCallback("onTradingManagerBuyFromPlayer", "registeredBuyCallback")
        Entity():registerCallback("onTradingManagerSellToPlayer", "registeredSellCallback")
        print("[EDE CB DEBUG] registerCallback done")
    end
end

function interactionPossible(playerIndex, option)
    return true
end

function initUI()
    ScriptUI():registerInteraction("EDE: Manual Callback Test", "onManualTest", 9)
end

-- Test: manually fire a sendCallback to see if our own script receives it
function onManualTest()
    if onClient() then
        invokeServerFunction("serverManualTest")
    end
end

function serverManualTest()
    if not onServer() then return end
    local player = Player(callingPlayer)
    if not player then return end

    player:sendChatMessage("EDE", ChatMessageType.Normal, "Firing manual sendCallback on this entity...")
    Entity():sendCallback("onTradingManagerBuyFromPlayer", "TestGood", 1, 100)
    player:sendChatMessage("EDE", ChatMessageType.Normal, "sendCallback fired. Check if any handler received it.")
end

-- Approach 1: function named exactly like the callback (auto-dispatch)
function onTradingManagerBuyFromPlayer(goodName, amount, price)
    print("[EDE CB DEBUG] AUTO-DISPATCH onTradingManagerBuyFromPlayer: " .. tostring(goodName))
    if callingPlayer then
        Player(callingPlayer):sendChatMessage("EDE", ChatMessageType.Normal,
            "AUTO-DISPATCH Buy: " .. tostring(goodName) .. " x" .. tostring(amount))
    end
end

function onTradingManagerSellToPlayer(goodName, amount, price)
    print("[EDE CB DEBUG] AUTO-DISPATCH onTradingManagerSellToPlayer: " .. tostring(goodName))
    if callingPlayer then
        Player(callingPlayer):sendChatMessage("EDE", ChatMessageType.Normal,
            "AUTO-DISPATCH Sell: " .. tostring(goodName) .. " x" .. tostring(amount))
    end
end

-- Approach 2: registered with different names
function registeredBuyCallback(goodName, amount, price)
    print("[EDE CB DEBUG] REGISTERED registeredBuyCallback: " .. tostring(goodName))
    if callingPlayer then
        Player(callingPlayer):sendChatMessage("EDE", ChatMessageType.Normal,
            "REGISTERED Buy: " .. tostring(goodName) .. " x" .. tostring(amount))
    end
end

function registeredSellCallback(goodName, amount, price)
    print("[EDE CB DEBUG] REGISTERED registeredSellCallback: " .. tostring(goodName))
    if callingPlayer then
        Player(callingPlayer):sendChatMessage("EDE", ChatMessageType.Normal,
            "REGISTERED Sell: " .. tostring(goodName) .. " x" .. tostring(amount))
    end
end

callable(nil, "serverManualTest")
