-- EDE Trade Hook — entity script that attaches to stations to intercept trades.
-- Supports BOTH cargo goods (TradingManager) and ship building resources (ResourceDepot).
--
-- Attach to a station:
--   /run Player().craft.selectedObject:addScriptOnce("entity/ede_trade_hook.lua")

package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

local TariffManager
local AgreementManager

function initialize()
    if onServer() then
        TariffManager = include("diplomacy/tariff_manager")
        AgreementManager = include("diplomacy/agreement_manager")

        -- Hook TradingManager callbacks (cargo goods)
        Entity():registerCallback("onTradingManagerBuyFromPlayer", "onStationBuyFromPlayer")
        Entity():registerCallback("onTradingManagerSellToPlayer", "onStationSellToPlayer")

        -- Hook ResourceDepot functions (ship building materials)
        wrapResourceDepot()
    end
end

function interactionPossible(playerIndex, option)
    return false
end

--- Wrap ResourceDepot.buy and ResourceDepot.sell to inject tariff logic.
--- Only applies if this station has a ResourceDepot script.
function wrapResourceDepot()
    -- ResourceDepot is a global namespace set by resourcetrader.lua
    if not ResourceDepot then return end

    -- Save originals
    if not ResourceDepot._ede_original_buy then
        ResourceDepot._ede_original_buy = ResourceDepot.buy
    end
    if not ResourceDepot._ede_original_sell then
        ResourceDepot._ede_original_sell = ResourceDepot.sell
    end

    -- Wrap buy (player BUYS resources FROM station — player pays credits)
    ResourceDepot.buy = function(material, amount)
        -- Get player before the trade
        local buyer = nil
        if callingPlayer then
            buyer = Player(callingPlayer)
        end

        -- Get price before trade executes (so we know what to tariff)
        local price = 0
        if buyer and material and amount and amount > 0 then
            local numTraded = amount
            -- Try to get the actual price
            if ResourceDepot.getBuyPriceAndTax then
                local faction = Faction(buyer.index) or buyer
                price = ResourceDepot.getBuyPriceAndTax(material, faction, numTraded) or 0
            end
        end

        -- Execute original trade
        ResourceDepot._ede_original_buy(material, amount)

        -- Apply tariff after trade completes
        if buyer and price > 0 then
            local materialName = Material(material - 1).name or ("Material " .. tostring(material))
            applyTradeAdjustment(buyer, materialName, amount, price, "purchase")
        end
    end

    -- Wrap sell (player SELLS resources TO station — player receives credits)
    ResourceDepot.sell = function(material, amount)
        local seller = nil
        if callingPlayer then
            seller = Player(callingPlayer)
        end

        local price = 0
        if seller and material and amount and amount > 0 then
            if ResourceDepot.getSellPriceAndTax then
                local faction = Faction(seller.index) or seller
                price = ResourceDepot.getSellPriceAndTax(material, faction, amount) or 0
            end
        end

        -- Execute original trade
        ResourceDepot._ede_original_sell(material, amount)

        -- Apply tariff after trade completes
        if seller and price > 0 then
            local materialName = Material(material - 1).name or ("Material " .. tostring(material))
            applyTradeAdjustment(seller, materialName, amount, price, "sale")
        end
    end
end

--- Apply tariff/agreement adjustment after a trade.
--- @param player userdata The Player object
--- @param goodName string Name of the good/resource traded
--- @param amount number Amount traded
--- @param price number Total price of the trade
--- @param tradeDirection string "sale" or "purchase"
function applyTradeAdjustment(player, goodName, amount, price, tradeDirection)
    if not player then return end

    local station = Entity()
    if not station then return end

    local stationFactionIndex = station.factionIndex
    local stationFaction = Faction(stationFactionIndex)
    if not stationFaction then return end

    local playerIndex = player.index
    local store = Server()

    -- Check tariff
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
                string.format("Tariff: -%s cr (%d%% on %s of %s at %s)",
                    tostring(net_adjustment), math.floor(tariff_rate * 100),
                    tradeDirection, goodName, station.name))
        else
            player:sendChatMessage("EDE", ChatMessageType.Warning,
                "Cannot pay tariff surcharge — insufficient credits!")
        end
    elseif net_adjustment < 0 then
        local bonus = math.abs(net_adjustment)
        player:receive("Trade agreement discount", bonus)
        player:sendChatMessage("EDE", ChatMessageType.Normal,
            string.format("Trade discount: +%s cr (%d%% with %s)",
                tostring(bonus), math.floor(agreement_rate * 100), stationFaction.name))
    end
end

-- TradingManager callbacks (cargo goods)
function onStationBuyFromPlayer(goodName, amount, price)
    if not onServer() then return end
    if not callingPlayer then return end
    local player = Player(callingPlayer)
    applyTradeAdjustment(player, goodName, amount, price, "sale")
end

function onStationSellToPlayer(goodName, amount, price)
    if not onServer() then return end
    if not callingPlayer then return end
    local player = Player(callingPlayer)
    applyTradeAdjustment(player, goodName, amount, price, "purchase")
end
