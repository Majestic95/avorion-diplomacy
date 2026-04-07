-- EDE Test Script — verifies mod loading works.
-- Requires: -dev launch option in Steam
--
-- Attach to a STATION (not your own ship — you can't interact with yourself):
--   1. Target a station (click on it)
--   2. /run Player().craft.selectedObject:addScript("entity/ede_test.lua")
--   3. Press F to interact with that station
--   4. Look for "EDE Mod Test" button
--
-- Remove when done:
--   /run Player().craft.selectedObject:removeScript("entity/ede_test.lua")

package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

-- Required: tells the engine whether the interaction button should be shown.
-- Without this function, the button may be silently hidden.
function interactionPossible(playerIndex, option)
    return true
end

-- Client-side: register an interaction option on the entity
function initUI()
    ScriptUI():registerInteraction("EDE Mod Test", "onTestPressed", 9)
end

-- Client-side: called when the player clicks the interaction button
function onTestPressed()
    if onClient() then
        invokeServerFunction("serverTestAction")
    end
end

-- Server-side: receives the button press and confirms the mod is working
function serverTestAction()
    if onServer() then
        local player = Player(callingPlayer)
        if not player then return end

        -- Send visible chat message (print() only goes to log files)
        player:sendChatMessage("EDE", ChatMessageType.Normal, "Mod is working! Testing modules...")

        -- Test that our lib modules load correctly
        local States = include("diplomacy/states")
        local Tariffs = include("economy/tariffs")
        local json = include("util/json")

        -- Quick smoke test of each module
        local state_type = States.Type.TARIFF
        local surcharge = Tariffs.calculateSurcharge(1000, 0.15)
        local encoded = json.encode({ test = true, value = surcharge })

        local msg = string.format(
            "All modules loaded OK! State=%s, Surcharge=%d, JSON=%s",
            state_type, surcharge, encoded
        )

        -- Send results to chat (visible in-game)
        player:sendChatMessage("EDE", ChatMessageType.Normal, msg)
    end
end

callable(nil, "serverTestAction")
