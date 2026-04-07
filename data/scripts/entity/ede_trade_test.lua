-- EDE Trade Test — sets up a test tariff and trade agreement for manual trade testing.
-- Attach to a station:
--   1. Target a station
--   2. /run Player().craft.selectedObject:addScript("entity/ede_trade_test.lua")
--   3. Press F, use the buttons to set up tariffs/agreements
--   4. Then trade normally at that station and watch for surcharges in chat
--
-- IMPORTANT: You must also attach the trade hooks to your player ONCE:
--   /run Player():addScriptOnce("player/ede_trade_hooks.lua")

package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

function interactionPossible(playerIndex, option)
    return true
end

function initUI()
    ScriptUI():registerInteraction("EDE: Set 15% Test Tariff", "onSetTariff", 8)
    ScriptUI():registerInteraction("EDE: Set 10% Trade Agreement", "onSetAgreement", 8)
    ScriptUI():registerInteraction("EDE: Clear All Test Data", "onClearAll", 8)
    ScriptUI():registerInteraction("EDE: Show Active States", "onShowStates", 8)
end

function onSetTariff()
    if onClient() then
        invokeServerFunction("serverSetTariff")
    end
end

function onSetAgreement()
    if onClient() then
        invokeServerFunction("serverSetAgreement")
    end
end

function onClearAll()
    if onClient() then
        invokeServerFunction("serverClearAll")
    end
end

function onShowStates()
    if onClient() then
        invokeServerFunction("serverShowStates")
    end
end

function serverSetTariff()
    if not onServer() then return end
    local player = Player(callingPlayer)
    if not player then return end

    local TariffManager = include("diplomacy/tariff_manager")
    local store = Server()
    local station = Entity()
    local stationFaction = Faction(station.factionIndex)

    -- Set tariff: station's faction tariffs the player
    local ok, err = TariffManager.declare(
        store,
        stationFaction.index,   -- imposer
        player.index,           -- target
        500,                    -- imposer score (bypass check with high value)
        500,                    -- target score
        0.15,                   -- 15% rate
        Server().unpausedRuntime -- timestamp
    )

    if ok then
        player:sendChatMessage("EDE", ChatMessageType.Normal,
            string.format("Test tariff set: %s charges YOU 15%% on all trades at their stations.",
                stationFaction.name))
    else
        player:sendChatMessage("EDE", ChatMessageType.Error,
            "Failed to set tariff: " .. tostring(err))
    end
end

function serverSetAgreement()
    if not onServer() then return end
    local player = Player(callingPlayer)
    if not player then return end

    local AgreementManager = include("diplomacy/agreement_manager")
    local store = Server()
    local station = Entity()
    local stationFaction = Faction(station.factionIndex)

    -- Propose and immediately accept a trade agreement
    local ok, err = AgreementManager.propose(
        store,
        player.index,           -- proposer
        stationFaction.index,   -- target
        0.10,                   -- player offers 10% discount to them
        0.10,                   -- player requests 10% discount from them
        Server().unpausedRuntime
    )

    if ok then
        AgreementManager.accept(store, player.index, stationFaction.index, Server().unpausedRuntime)
        player:sendChatMessage("EDE", ChatMessageType.Normal,
            string.format("Trade agreement set: mutual 10%% discount with %s.", stationFaction.name))
    else
        player:sendChatMessage("EDE", ChatMessageType.Error,
            "Failed to set agreement: " .. tostring(err))
    end
end

function serverClearAll()
    if not onServer() then return end
    local player = Player(callingPlayer)
    if not player then return end

    local TariffManager = include("diplomacy/tariff_manager")
    local AgreementManager = include("diplomacy/agreement_manager")
    local store = Server()
    local station = Entity()
    local stationFaction = Faction(station.factionIndex)

    TariffManager.remove(store, stationFaction.index, player.index)
    TariffManager.remove(store, player.index, stationFaction.index)
    AgreementManager.cancel(store, player.index, stationFaction.index)

    player:sendChatMessage("EDE", ChatMessageType.Normal, "All test tariffs and agreements cleared.")
end

function serverShowStates()
    if not onServer() then return end
    local player = Player(callingPlayer)
    if not player then return end

    local TariffManager = include("diplomacy/tariff_manager")
    local AgreementManager = include("diplomacy/agreement_manager")
    local store = Server()
    local station = Entity()
    local stationFaction = Faction(station.factionIndex)

    local tariff = TariffManager.get(store, stationFaction.index, player.index)
    local agreement = AgreementManager.getActive(store, player.index, stationFaction.index)

    if tariff and tariff.active then
        player:sendChatMessage("EDE", ChatMessageType.Normal,
            string.format("Active tariff: %s charges you %d%%",
                stationFaction.name, math.floor(tariff.rate * 100)))
    else
        player:sendChatMessage("EDE", ChatMessageType.Normal, "No active tariff with " .. stationFaction.name)
    end

    if agreement then
        player:sendChatMessage("EDE", ChatMessageType.Normal,
            string.format("Active trade agreement with %s", stationFaction.name))
    else
        player:sendChatMessage("EDE", ChatMessageType.Normal, "No trade agreement with " .. stationFaction.name)
    end
end

callable(nil, "serverSetTariff")
callable(nil, "serverSetAgreement")
callable(nil, "serverClearAll")
callable(nil, "serverShowStates")
