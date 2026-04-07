-- EDE Trade Hooks — applies tariff surcharges and agreement discounts to trades.
-- This is a PLAYER script that listens for trade callbacks on the player.
--
-- Attach: Player():addScriptOnce("player/ede_trade_hooks.lua")
-- Remove: Player():removeScript("player/ede_trade_hooks.lua")
--
-- How it works:
--   Vanilla TradingManager fires callbacks AFTER a trade completes.
--   We listen for those callbacks, check for active tariffs/agreements,
--   and apply surcharges or refunds as separate credit transactions.

package.path = package.path .. ";data/scripts/lib/?.lua"

local TariffManager
local AgreementManager

-- Initialize on server and register for trade callbacks
function initialize()
    if onServer() then
        TariffManager = include("diplomacy/tariff_manager")
        AgreementManager = include("diplomacy/agreement_manager")

        -- Register to receive trade callbacks from vanilla TradingManager
        local player = Player()
        player:registerCallback("onTradingManagerBuyFromPlayer", "onTradingManagerBuyFromPlayer")
        player:registerCallback("onTradingManagerSellToPlayer", "onTradingManagerSellToPlayer")
    end
end

--- Find the station the player is currently trading with.
--- The player's craft must be docked or interacting with a station.
local function findTradingStation()
    local player = Player()
    if not player then return nil end

    local craft = player.craft
    if not craft then return nil end

    -- Try selectedObject first (the station the player has targeted)
    if craft.selectedObject then
        local selected = Entity(craft.selectedObject)
        if selected and selected.isStation then
            return selected
        end
    end

    -- Fallback: try dockedTo
    if craft.dockedTo then
        local docked = Entity(craft.dockedTo)
        if docked then
            return docked
        end
    end

    return nil
end

--- Apply tariff/agreement adjustments after a trade.
--- @param price number The original trade price
--- @param action string "sold" or "purchased" (for chat message)
local function applyTradeAdjustment(price, action)
    local player = Player()
    if not player then return end

    local station = findTradingStation()
    if not station then return end

    local stationFactionIndex = station.factionIndex
    if not stationFactionIndex then return end

    local stationFaction = Faction(stationFactionIndex)
    if not stationFaction then return end

    local playerIndex = player.index
    local store = Server()

    -- Check tariff: either direction between station faction and player
    local surcharge, tariff_rate = TariffManager.calculateSurcharge(
        store, stationFactionIndex, playerIndex, price
    )

    -- Check trade agreement discount
    local _, agreement_rate = AgreementManager.calculateDiscount(
        store, playerIndex, stationFactionIndex, price
    )

    local net_adjustment = surcharge
    if agreement_rate > 0 then
        local refund = math.floor(price * agreement_rate + 0.5)
        net_adjustment = net_adjustment - refund
    end

    if net_adjustment > 0 then
        -- Player owes a tariff surcharge
        if player:canPayMoney(net_adjustment) then
            player:pay("Tariff surcharge", net_adjustment)

            -- Revenue goes to the imposing faction
            local tariff = TariffManager.get(store, stationFactionIndex, playerIndex)
            if not tariff then
                tariff = TariffManager.get(store, playerIndex, stationFactionIndex)
            end
            if tariff and tariff.imposer then
                local imposer = Faction(tariff.imposer)
                if imposer then
                    imposer:receive("Tariff revenue from trade", net_adjustment)
                end
                TariffManager.recordRevenue(store, tariff.imposer, tariff.target, net_adjustment)
            end

            player:sendChatMessage("EDE", ChatMessageType.Normal,
                string.format("Tariff surcharge: -%s credits (%d%% tariff on %s with %s)",
                    tostring(net_adjustment), math.floor(tariff_rate * 100),
                    action, stationFaction.name))
        else
            player:sendChatMessage("EDE", ChatMessageType.Warning,
                "Cannot pay tariff surcharge — insufficient credits!")
        end
    elseif net_adjustment < 0 then
        -- Player gets a net refund (agreement discount exceeds tariff)
        local bonus = math.abs(net_adjustment)
        player:receive("Trade agreement discount", bonus)
        player:sendChatMessage("EDE", ChatMessageType.Normal,
            string.format("Trade agreement bonus: +%s credits (%d%% discount with %s)",
                tostring(bonus), math.floor(agreement_rate * 100), stationFaction.name))
    end
end

-- Callback: player SELLS goods to a station (station buys from player)
function onTradingManagerBuyFromPlayer(goodName, amount, price)
    if not onServer() then return end
    applyTradeAdjustment(price, "sale")
end

-- Callback: player BUYS goods from a station (station sells to player)
function onTradingManagerSellToPlayer(goodName, amount, price)
    if not onServer() then return end
    applyTradeAdjustment(price, "purchase")
end
