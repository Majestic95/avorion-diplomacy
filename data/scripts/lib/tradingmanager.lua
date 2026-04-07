
package.path = package.path .. ";data/scripts/lib/?.lua"
include ("galaxy")
include ("utility")
include ("goods")
include ("stringutility")
include ("player")
include ("faction")
include ("merchantutility")
include ("relations")
include ("randomext")
include ("callable")

-- [EDE MOD] Tariff/agreement hooks for cargo trades
-- Self-contained: no include() of EDE modules (avoids interfering with TradingManager loading)
-- Reads tariff/agreement state directly from Server():getValue()

local function edeJsonDecode(str)
    if not str or type(str) ~= "string" then return nil end
    local first = str:sub(1, 1)
    if first ~= "{" and first ~= "[" then return nil end
    -- Minimal JSON object decoder for {key:value} pairs
    local ok, result = pcall(function()
        local t = {}
        for k, v in str:gmatch('"([^"]+)":([^,}]+)') do
            v = v:match("^%s*(.-)%s*$") -- trim
            if v == "true" then t[k] = true
            elseif v == "false" then t[k] = false
            elseif v == "null" then t[k] = nil
            elseif v:sub(1,1) == '"' then t[k] = v:sub(2, -2)
            else t[k] = tonumber(v) end
        end
        return t
    end)
    if ok then return result end
    return nil
end

local function edeApplyTradeTariff(shipFaction, player, price, goodName, tradeDirection)
    if not shipFaction or not player or price <= 0 then return end
    local station = Entity()
    if not station then return end
    local stationFactionIndex = station.factionIndex
    local store = Server()
    local playerIndex = shipFaction.index

    -- Check tariff in both directions
    local tariffRaw = store:getValue("ede_tariff_" .. stationFactionIndex .. "_" .. playerIndex)
        or store:getValue("ede_tariff_" .. playerIndex .. "_" .. stationFactionIndex)
    local tariff = edeJsonDecode(tariffRaw)
    local tariff_rate = (tariff and tariff.active and tariff.rate) or 0

    -- Check agreement
    local a = math.min(playerIndex, stationFactionIndex)
    local b = math.max(playerIndex, stationFactionIndex)
    local agreeRaw = store:getValue("ede_agreement_" .. a .. "_" .. b)
    local agreement = edeJsonDecode(agreeRaw)
    local agreement_rate = 0
    if agreement and agreement.status == "active" and agreement.discounts then
        agreement_rate = agreement.discounts[tostring(stationFactionIndex)] or 0
    end

    local surcharge = 0
    if tariff_rate > 0 then
        surcharge = math.floor(price * tariff_rate + 0.5)
    end

    local net = surcharge
    if agreement_rate > 0 then
        net = net - math.floor(price * agreement_rate + 0.5)
    end

    if net > 0 then
        if shipFaction:canPayMoney(net) then
            shipFaction:pay("Tariff surcharge", net)
            if tariff and tariff.imposer then
                local imposer = Faction(tariff.imposer)
                if imposer then imposer:receive("Tariff revenue", net) end
            end
            player:sendChatMessage("EDE", ChatMessageType.Normal,
                string.format("Tariff: -%s cr (%d%% on %s of %s)",
                    tostring(net), math.floor(tariff_rate * 100), tradeDirection, goodName))
        end
    elseif net < 0 then
        local bonus = math.abs(net)
        shipFaction:receive("Trade agreement discount", bonus)
        player:sendChatMessage("EDE", ChatMessageType.Normal,
            string.format("Trade discount: +%s cr (%d%% on %s of %s)",
                tostring(bonus), math.floor(agreement_rate * 100), tradeDirection, goodName))
    end
end
-- [END EDE MOD]

local TradingManager = {}
TradingManager.__index = TradingManager

local PublicNamespace = {}

local function new()
    local instance = {}

    instance.buyPriceFactor = 1
    instance.sellPriceFactor = 1

    -- tax is the amount of money the owner of the entity gets from transactions
    -- for example this can be 0.1 at a factory, meaning the owner gets 10% of every transaction done at this factory
    instance.tax = 0.0

    -- the amount of money the owner of the entity pays or receives directly through transactions
    instance.factionPaymentFactor = 1.0
    instance.supplyDemandInfluence = 1.0
    instance.stockInfluence = 1.0
    instance.minimumCargoBay = 25000

    instance.boughtGoods = {}
    instance.soldGoods = {}

    instance.numSold = 0
    instance.numBought = 0

    instance.buyFromOthers = true
    instance.sellToOthers = true
    instance.relationsThreshold = nil

    instance.activelyRequest = false
    instance.activelySell = false

    instance.deliveredStations = {}
    instance.deliveringStations = {}

    instance.ownSupplyTypes = {}

    instance.policies =
    {
        sellsIllegal = false,
        buysIllegal = false,

        sellsStolen = false,
        buysStolen = false,

        sellsSuspicious = false,
        buysSuspicious = false,
    }

    instance.stats =
    {
        moneySpentOnGoods = 0,
        moneyGainedFromGoods = 0,
        moneyGainedFromTax = 0,
    }

    -- UI
    instance.boughtLines = {}
    instance.soldLines = {}

    instance.guiInitialized = false
    instance.useTimeCounter = 0 -- time counter for using up bought products
    instance.useUpGoodsEnabled = true

    return setmetatable(instance, TradingManager)
end

function TradingManager:getBuysFromOthers()
    return self.buyFromOthers
end

function TradingManager:getSellsToOthers()
    return self.sellToOthers
end

function TradingManager:setBuysFromOthers(value)
    self.buyFromOthers = value
end

function TradingManager:setSellsToOthers(value)
    self.sellToOthers = value
end

function TradingManager:setBuyPriceFactor(value)
    self.buyPriceFactor = value
end

function TradingManager:setSellPriceFactor(value)
    self.sellPriceFactor = value
end

-- help functions
function TradingManager:isSoldBySelf(good)
    if good.illegal and not self.policies.sellsIllegal then
        local msg = "This station doesn't sell illegal goods."%_t
        return false, msg
    end

    if good.stolen and not self.policies.sellsStolen then
        local msg = "This station doesn't sell stolen goods."%_t
        return false, msg
    end

    if good.suspicious and not self.policies.sellsSuspicious then
        local msg = "This station doesn't sell suspicious goods."%_t
        return false, msg
    end

    -- don't trade resource ores
    local tags = good.tags
    if tags.scrap or tags.ore then
        return false, "This station doesn't sell this."%_t
    end

    return true
end

function TradingManager:isBoughtBySelf(good)
    if good.illegal and not self.policies.buysIllegal then
        local msg = "This station doesn't buy illegal goods."%_t
        return false, msg
    end

    if good.stolen and not self.policies.buysStolen then
        local msg = "This station doesn't buy stolen goods."%_t
        return false, msg
    end

    if good.suspicious and not self.policies.buysSuspicious then
        local msg = "This station doesn't buy suspicious goods."%_t
        return false, msg
    end

    -- don't trade resource ores
    local tags = good.tags
    if tags.scrap or tags.ore then
        return false, "This station doesn't buy this."%_t
    end

    return true
end

function TradingManager:restoreTradingGoods(data)
    self.buyPriceFactor = data.buyPriceFactor
    self.sellPriceFactor = data.sellPriceFactor
    self.policies = data.policies
    self.stats = data.stats or self.stats
    self.ownSupplyTypes = data.ownSupplyTypes or self.ownSupplyTypes
    self.supplyDemandInfluence = data.supplyDemandInfluence or self.supplyDemandInfluence
    self.stockInfluence = data.stockInfluence or self.stockInfluence

    self.boughtGoods = {}
    for _, g in pairs(data.boughtGoods) do
        table.insert(self.boughtGoods, tableToGood(g))
    end

    self.soldGoods = {}
    for _, g in pairs(data.soldGoods) do
        table.insert(self.soldGoods, tableToGood(g))
    end

    self.numBought = #self.boughtGoods
    self.numSold = #self.soldGoods

    if data.buyFromOthers == nil then
        self.buyFromOthers = true
    else
        self.buyFromOthers = data.buyFromOthers
    end

    if data.sellToOthers == nil then
        self.sellToOthers = true
    else
        self.sellToOthers = data.sellToOthers
    end

    self.activelyRequest = data.activelyRequest or false
    self.activelySell = data.activelySell or false

    self.deliveredStations = data.deliveredStations or {}
    self.deliveringStations = data.deliveringStations or {}
end

function TradingManager:secureTradingGoods()
    local data = {}
    data.buyPriceFactor = self.buyPriceFactor
    data.sellPriceFactor = self.sellPriceFactor
    data.policies = self.policies
    data.stats = self.stats
    data.ownSupplyTypes = self.ownSupplyTypes
    data.supplyDemandInfluence = self.supplyDemandInfluence
    data.stockInfluence = self.stockInfluence

    data.buyFromOthers = self.buyFromOthers
    data.sellToOthers = self.sellToOthers
    data.activelyRequest = self.activelyRequest
    data.activelySell = self.activelySell

    data.deliveredStations = self.deliveredStations
    data.deliveringStations = self.deliveringStations


    data.boughtGoods = {}
    for _, g in pairs(self.boughtGoods) do
        table.insert(data.boughtGoods, goodToTable(g))
    end

    data.soldGoods = {}
    for _, g in pairs(self.soldGoods) do
        table.insert(data.soldGoods, goodToTable(g))
    end

    return data
end

function TradingManager:initializeTrading(boughtGoodsIn, soldGoodsIn, policiesIn)

    local entity = Entity()

    self.policies = policiesIn or self.policies

    -- generate goods only once, this adds physical goods to the entity
    local generated = entity:getValue("goods_generated")
    if not generated or generated ~= 1 then
        entity:setValue("goods_generated", 1)
        generated = false
    else
        generated = true
    end

    boughtGoodsIn = boughtGoodsIn or {}
    soldGoodsIn = soldGoodsIn or {}

    self.numBought = #boughtGoodsIn
    self.numSold = #soldGoodsIn

    if not generated then
        local boughtStock, soldStock = self:getInitialGoods(boughtGoodsIn, soldGoodsIn)

        for good, amount in pairs(boughtStock) do
            entity:addCargo(good, amount)
        end

        for good, amount in pairs(soldStock) do
            entity:addCargo(good, amount)
        end
    end

    self.boughtGoods = {}

    local resourceAmount = math.random(1, 3)

    for i, v in ipairs(boughtGoodsIn) do
        table.insert(self.boughtGoods, v)
    end

    self.soldGoods = {}

    for i, v in ipairs(soldGoodsIn) do
        table.insert(self.soldGoods, v)
    end

    self.numBought = #self.boughtGoods
    self.numSold = #self.soldGoods
end

function TradingManager:getInitialGoods(boughtGoodsIn, soldGoodsIn)
    local resourceAmount = math.random(1, 5)

    local boughtStockByGood = {}
    local soldStockByGood = {}

    for _, v in ipairs(boughtGoodsIn) do
        local maxStock = self:getMaxStock(v)
        if maxStock > 0 then

            local amount
            if resourceAmount == 1 then
                -- station has few resources available
                amount = math.random(0, maxStock * 0.15)
            else
                -- normal amount of resources available
                amount = math.random(maxStock * 0.1, maxStock * 0.5)
            end

            -- limit by value
            local maxValue = 300 * 1000 * Balancing_GetSectorRichnessFactor(Sector():getCoordinates())
            amount = math.min(amount, math.floor(maxValue / v.price))

            boughtStockByGood[v] = amount
        end
    end

    for _, v in ipairs(soldGoodsIn) do
        local maxStock = self:getMaxStock(v)
        if maxStock > 0 then

            local amount
            if resourceAmount == 1 then
                -- resources are used up -> more products
                amount = math.random(maxStock * 0.4, maxStock)
            else
                amount = math.random(0, maxStock * 0.6)
            end

            -- limit to 500k value at max
            local maxValue = 500 * 1000 * Balancing_GetSectorRichnessFactor(Sector():getCoordinates())
            amount = math.min(amount, math.floor(maxValue / v.price))

            soldStockByGood[v] = amount
        end
    end

    return boughtStockByGood, soldStockByGood
end

function TradingManager:simulatePassedTime(timeSinceLastSimulation)
    local boughtStock, soldStock = self:getInitialGoods(self.boughtGoods, self.soldGoods)
    local entity = Entity()

    local factor = math.max(0, math.min(1, (timeSinceLastSimulation - 10 * 60) / (100 * 60)))

    -- interpolate to new stock
    for good, amount in pairs(boughtStock) do
        local curAmount = entity:getCargoAmount(good)
        local diff = math.floor((amount - curAmount) * factor)

        if diff > 0 then
            self:increaseGoods(good.name, diff)
        elseif diff < 0 then
            self:decreaseGoods(good.name, -diff)
        end
    end

    for good, amount in pairs(soldStock) do
        local curAmount = entity:getCargoAmount(good)
        local diff = math.floor((amount - curAmount) * factor)

        if diff > 0 then
            self:increaseGoods(good.name, diff)
        elseif diff < 0 then
            self:decreaseGoods(good.name, -diff)
        end
    end
end

function TradingManager:requestGoods()
    invokeServerFunction("sendGoods")
end

function TradingManager:sendGoods()
    local player = Player(callingPlayer)
    invokeClientFunction(player, "receiveGoods", self.buyPriceFactor, self.sellPriceFactor, self.boughtGoods, self.soldGoods, self.policies, self.stats, self.ownSupplyTypes, self.supplyDemandInfluence, self.stockInfluence)
end

function TradingManager:receiveGoods(buyFactor, sellFactor, boughtGoods_in, soldGoods_in, policies_in, stats_in, ownSupply_in, supplyDemandInfluence_in, stockInfluence_in)

    self.buyPriceFactor = buyFactor
    self.sellPriceFactor = sellFactor

    self.policies = policies_in
    self.stats = stats_in
    self.ownSupplyTypes = ownSupply_in

    self.boughtGoods = boughtGoods_in
    self.soldGoods = soldGoods_in

    self.supplyDemandInfluence = supplyDemandInfluence_in
    self.stockInfluence = stockInfluence_in

    self.receivedGoods = true

    table.sort(self.boughtGoods, function(a, b) return a:displayName(1) < b:displayName(1) end)
    table.sort(self.soldGoods, function(a, b) return a:displayName(1) < b:displayName(1) end)

    self.numBought = #self.boughtGoods
    self.numSold = #self.soldGoods

    if PublicNamespace.window and PublicNamespace.window.visible then
        self:refreshUI()
    end
end

function TradingManager:refreshUI()

    local player = Player()
    local playerCraft = player.craft
    if not playerCraft then return end

    if playerCraft.factionIndex == player.allianceIndex then
        player = player.alliance
    end

    for i, good in ipairs(self.boughtGoods) do
        self:updateBoughtGoodGui(i, good, self:getBuyPrice(good.name, player.index))
    end

    for i, good in ipairs(self.soldGoods) do
        self:updateSoldGoodGui(i, good, self:getSellPrice(good.name, player.index))
    end

end

function TradingManager:updateBoughtGoodGui(index, good, price)
    if not self.guiInitialized then return end

    local maxAmount = self:getMaxStock(good)
    local amount = self:getNumGoods(good.name)

    if not index then
        for i, g in pairs(self.boughtGoods) do
            if g.name == good.name then
                index = i
                break
            end
        end
    end

    if not index then return end

    local line = self.boughtLines[index]
    if not line then return end

    line.name.caption = good:displayName(100)
    line.name.color = good.color
    local description = good.displayDescription
    if description == "" then
        line.name.tooltip = nil
        line.icon.tooltip = nil
    else
        line.name.tooltip = description
        line.icon.tooltip = description
    end
    line.stock.caption = amount .. "/" .. maxAmount
    line.price.caption = createMonetaryString(price)
    line.size.caption = round(good.size, 2)
    line.icon.picture = good.icon

    local ownCargo = 0
    local ship = Entity(Player().craftIndex)
    if ship then
        ownCargo = ship:getCargoAmount(good)
    end
    if ownCargo == 0 then
        ownCargo = "-"
        line.you.tooltip = nil
    else
        line.you.tooltip = "You can sell ${amount} more of this."%_t % {amount = ownCargo}
    end
    line.you.caption = tostring(ownCargo)

    line:show()
end

function TradingManager:updateSoldGoodGui(index, good, price)

    if not self.guiInitialized then return end

    local maxAmount = self:getMaxStock(good)
    local amount = self:getNumGoods(good.name)

    if not index then
        for i, g in pairs(self.soldGoods) do
            if g.name == good.name then
                index = i
                break
            end
        end
    end

    if not index then return end

    local line = self.soldLines[index]
    if not line then return end

    line.icon.picture = good.icon
    line.name.caption = good:displayName(100)
    line.name.color = good.color
    local description = good.displayDescription
    if description == "" then
        line.name.tooltip = nil
        line.icon.tooltip = nil
    else
        line.name.tooltip = description
        line.icon.tooltip = description
    end
    line.stock.caption = amount .. "/" .. maxAmount
    line.price.caption = createMonetaryString(price)
    line.size.caption = round(good.size, 2)

    for i, good in pairs(self.soldGoods) do
        local line = self.soldLines[i]

        local ownCargo = 0
        local ship = Entity(Player().craftIndex)
        if ship then
            ownCargo = math.floor((ship.freeCargoSpace or 0) / good.size)
        end

        if ownCargo == 0 then ownCargo = "-" end
        line.you.caption = tostring(ownCargo)
        line.you.tooltip = "You can buy ${amount} more of this."%_t % {amount = ownCargo}
    end

    line:show()

end

function TradingManager:updateBoughtGoodAmount(name)

    local good = self:getBoughtGoodByName(name)

    if good ~= nil then -- it's possible that the production may start before the initialization of the client version of the factory
        local player = Player()
        local playerCraft = player.craft
        if playerCraft and playerCraft.factionIndex == player.allianceIndex then
            player = player.alliance
        end

        self:updateBoughtGoodGui(nil, good, self:getBuyPrice(good.name, player.index))
    end

end

function TradingManager:updateSoldGoodAmount(name)

    local good = self:getSoldGoodByName(name)

    if good ~= nil then -- it's possible that the production may start before the initialization of the client version of the factory
        local player = Player()
        local playerCraft = player.craft
        if playerCraft and playerCraft.factionIndex == player.allianceIndex then
            player = player.alliance
        end

        self:updateSoldGoodGui(nil, good, self:getSellPrice(good.name, player.index))
    end
end

function TradingManager:buildBuyGui(window)
    self:buildGui(window, 1)
end

function TradingManager:buildSellGui(window)
    self:buildGui(window, 0)
end

function TradingManager:buildGui(window, guiType)

    local buttonCaption = ""
    local buttonCallback = ""
    local textCallback = ""

    if guiType == 1 then
        buttonCaption = "Buy"%_t
        buttonCallback = "onBuyButtonPressed"
        textCallback = "onBuyTextEntered"
    else
        buttonCaption = "Sell"%_t
        buttonCallback = "onSellButtonPressed"
        textCallback = "onSellTextEntered"
    end

    local size = window.size

--    window:createFrame(Rect(size))

    local pictureX = 270
    local nameX = 10
    local stockX = 310
    local volX = 460
    local priceX = 530
    local youX = 630
    local textBoxX = 720
    local buttonX = 790

    local buttonSize = 70

    -- header
    window:createLabel(vec2(nameX, 0), "NAME"%_t, 15)
    window:createLabel(vec2(stockX, 0), "STOCK"%_t, 15)

    local l = window:createLabel(Rect(priceX, 0, youX - 10, 35), "¢", 15)
    l:setTopRightAligned()

    local l = window:createLabel(Rect(volX, 0, priceX - 10, 35), "VOL"%_t, 15)
    l:setTopRightAligned()

    if guiType == 1 then
        local label = window:createLabel(Rect(youX, 0, textBoxX - 20, 35), "MAX"%_t, 15)
        label:setTopRightAligned()
    else
        local l = window:createLabel(Rect(youX, 0, textBoxX - 20, 35), "YOU"%_t, 15)
        l:setTopRightAligned()
    end

    local y = 30
    for i = 1, 15 do

        local yText = y + 6

        local frame = window:createFrame(Rect(0, y, textBoxX - 10, 30 + y))

        local icon = window:createPicture(Rect(pictureX, yText - 5, 29 + pictureX, 29 + yText - 5), "")
        local nameLabel = window:createLabel(vec2(nameX, yText), "", 15)
        local stockLabel = window:createLabel(vec2(stockX, yText), "", 15)
        local priceLabel = window:createLabel(Rect(priceX, yText, youX - 10, yText + 35), "", 15)
        local sizeLabel = window:createLabel(Rect(volX, yText, priceX - 10, yText + 35), "", 15)
        local youLabel = window:createLabel(Rect(youX, yText, textBoxX - 20, yText + 35), "", 15)
        local numberTextBox = window:createTextBox(Rect(textBoxX, yText - 6, 60 + textBoxX, 30 + yText - 6), textCallback)
        local button = window:createButton(Rect(buttonX, yText - 6, window.size.x, 30 + yText - 6), buttonCaption, buttonCallback)

        priceLabel:setTopRightAligned()
        sizeLabel:setTopRightAligned()
        youLabel:setTopRightAligned()

        nameLabel.width = pictureX - nameX
        nameLabel.shortenText = true

        button.maxTextSize = 16

        numberTextBox.text = "0"
        numberTextBox.allowedCharacters = "0123456789"
        numberTextBox.clearOnClick = 1

        icon.isIcon = 1

        local show = function (self)
            self.icon:show()
            self.frame:show()
            self.name:show()
            self.stock:show()
            self.price:show()
            self.size:show()
            self.number:show()
            self.button:show()
            self.you:show()
        end
        local hide = function (self)
            self.icon:hide()
            self.frame:hide()
            self.name:hide()
            self.stock:hide()
            self.price:hide()
            self.size:hide()
            self.number:hide()
            self.button:hide()
            self.you:hide()
        end

        local line = {icon = icon, frame = frame, name = nameLabel, stock = stockLabel, price = priceLabel, you = youLabel, size = sizeLabel, number = numberTextBox, button = button, show = show, hide = hide}
        line:hide()

        if guiType == 1 then
            table.insert(self.soldLines, line)
        else
            table.insert(self.boughtLines, line)
        end

        y = y + 35
    end

end

function TradingManager:onBuyTextEntered(textBox)

    local enteredNumber = tonumber(textBox.text)
    if enteredNumber == nil then
        enteredNumber = 0
    end

    local newNumber = enteredNumber

    local goodIndex = nil
    for i, line in pairs(self.soldLines) do
        if line.number.index == textBox.index then
            goodIndex = i
            break
        end
    end

    if goodIndex == nil then return end

    local good = self.soldGoods[goodIndex]

    if not good then
        -- no error reporting necessary, it's possible the goods got reset while waiting for sync
        -- self:reportError("Good with index " .. goodIndex .. " isn't sold.")
        return
    end

    -- make sure the player can't buy more than the station has in stock
    local stock = self:getNumGoods(good.name)

    if stock < newNumber then
        newNumber = stock
    end

    local player = Player()
    local ship = player.craft
    local shipFaction
    if ship.factionIndex == player.allianceIndex then
        shipFaction = player.alliance
    end
    if shipFaction == nil then
        shipFaction = player
    end
    if ship.freeCargoSpace == nil then return end --> no cargo bay

    -- make sure the player does not buy more than he can have in his cargo bay
    local maxShipHold = math.floor(ship.freeCargoSpace / good.size)
    local msg

    if maxShipHold < newNumber then
        newNumber = maxShipHold
        if newNumber == 0 then
            msg = "Not enough space in your cargo bay!"%_t
        else
            msg = "You can only store ${amount} of this good!"%_t % {amount = newNumber}
        end
    end

    -- make sure the player does not buy more than he can afford (if this isn't his station)
    if Faction().index ~= shipFaction.index then
        local maxAffordable = math.floor(shipFaction.money / self:getSellPrice(good.name, shipFaction.index))
        if shipFaction.infiniteResources then maxAffordable = math.huge end

        if maxAffordable < newNumber then
            newNumber = maxAffordable

            if newNumber == 0 then
                msg = "You can't afford any of this good!"%_t
            else
                msg = "You can only afford ${amount} of this good!"%_t % {amount = newNumber}
            end
        end
    end

    if msg then
        self:sendError(nil, msg)
    end

    if newNumber ~= enteredNumber then
        textBox.text = newNumber
    end
end

function TradingManager:onSellTextEntered(textBox)

    local enteredNumber = tonumber(textBox.text)
    if enteredNumber == nil then
        enteredNumber = 0
    end

    local newNumber = enteredNumber

    local goodIndex = nil
    for i, line in pairs(self.boughtLines) do
        if line.number.index == textBox.index then
            goodIndex = i
            break
        end
    end
    if goodIndex == nil then return end

    local good = self.boughtGoods[goodIndex]
    if not good then
        -- no error reporting necessary, it's possible the goods got reset while waiting for sync
        -- self:reportError("Good with index " .. goodIndex .. " isn't bought");
        return
    end

    local stock = self:getNumGoods(good.name)

    local maxAmountPlaceable = math.max(0, self:getMaxStock(good) - stock)
    if maxAmountPlaceable < newNumber then
        newNumber = maxAmountPlaceable
    end


    local ship = Player().craft

    local msg

    -- make sure the player does not sell more than he has in his cargo bay
    local amountOnPlayerShip = ship:getCargoAmount(good)
    if amountOnPlayerShip == nil then return end --> no cargo bay

    if amountOnPlayerShip < newNumber then
        newNumber = amountOnPlayerShip
        if newNumber == 0 then
            msg = "You don't have any of this!"%_t
        end
    end

    if msg then
        self:sendError(nil, msg)
    end

    -- maximum number of sellable things is the amount the player has on his ship
    if newNumber ~= enteredNumber then
        textBox.text = newNumber
    end
end

function TradingManager:onBuyButtonPressed(button)

    local shipIndex = Player().craftIndex
    local goodIndex = nil

    for i, line in ipairs(self.soldLines) do
        if line.button.index == button.index then
            goodIndex = i
        end
    end

    if goodIndex == nil then
        print("internal error, good matching 'Buy' button doesn't exist.")
        return
    end

    local amount = self.soldLines[goodIndex].number.text
    if amount == "" then
        amount = 0
    else
        amount = tonumber(amount)
    end

    local good = self.soldGoods[goodIndex]
    if not good then
        -- no error reporting necessary, it's possible the goods got reset while waiting for sync
        -- self:reportError("Good with index " .. goodIndex .. " of buy button not found.")
        return
    end

    invokeServerFunction("sellToShip", shipIndex, good.name, amount)
end

function TradingManager:onSellButtonPressed(button)

    local shipIndex = Player().craftIndex
    local goodIndex = nil

    for i, line in ipairs(self.boughtLines) do
        if line.button.index == button.index then
            goodIndex = i
        end
    end

    if goodIndex == nil then
        return
    end

    local amount = self.boughtLines[goodIndex].number.text
    if amount == "" then
        amount = 0
    else
        amount = tonumber(amount)
    end

    local good = self.boughtGoods[goodIndex]
    if not good then
        -- no error reporting necessary, it's possible the goods got reset while waiting for sync
        -- self:reportError("Good with index " .. goodIndex .. " of sell button not found.")
        return
    end

    invokeServerFunction("buyFromShip", shipIndex, good.name, amount)

end

function TradingManager:sendError(faction, msg, ...)
    if onServer() then
        faction:sendChatMessage(Entity(), 1, msg, ...)
    elseif onClient() then
        displayChatMessage(msg, Entity().title, 1)
    end
end

function TradingManager:transferMoney(owner, from, to, price, fromDescription, toDescription)
    if from.index == to.index then return end

    local ownerMoney = price * self.factionPaymentFactor

    if owner.index == from.index then
        from:pay(fromDescription or "", ownerMoney)
        to:receive(toDescription or "", price)
        self.stats.moneySpentOnGoods = self.stats.moneySpentOnGoods + ownerMoney
    elseif owner.index == to.index then
        from:pay(fromDescription or "", price)
        to:receive(toDescription or "", ownerMoney)
        self.stats.moneyGainedFromGoods = self.stats.moneyGainedFromGoods + ownerMoney
    else
        from:pay(fromDescription or "", price)
        to:receive(toDescription or "", price)
    end

    receiveTransactionTax(Entity(), price * self.tax)

    -- log tax
    local tax = round(price * self.tax)
    if tax > 0 then
        self.stats.moneyGainedFromTax = self.stats.moneyGainedFromTax + tax
    end
end

function TradingManager:buyFromShip(shipIndex, goodName, amount, noDockCheck)
    local shipFaction, ship = getInteractingFactionByShip(shipIndex, callingPlayer, AlliancePrivilege.SpendResources)
    if not shipFaction then return end

    if callingPlayer then noDockCheck = nil end

    local stationFaction = Faction()

    -- check if it even buys
    if self.buyFromOthers == false and stationFaction.index ~= shipFaction.index then
        self:sendError(shipFaction, "This object doesn't buy goods from others."%_t)
        return
    end

    -- check if the good can be bought
    if not self:getBoughtGoodByName(goodName) == nil then
        self:sendError(shipFaction, "%s isn't bought."%_t, goodName)
        return
    end

    if ship.freeCargoSpace == nil then
        self:sendError(shipFaction, "Your ship has no cargo bay!"%_t)
        return
    end

    local station = Entity()

    -- check if the relations are ok
    if self.relationsThreshold then
        local relations = stationFaction:getRelations(shipFaction.index)
        if relations < self.relationsThreshold then
            self:sendError(shipFaction, "Relations aren't good enough to trade!"%_t)
            return
        end
    end

    -- check if the specific good from the player can be bought (ie. it's not illegal or something like that)
    local cargos = ship:findCargos(goodName)
    local good = nil
    local msg = "You don't have any %s to sell!"%_t
    local args = {goodName}

    for g, amount in pairs(cargos) do
        local ok
        ok, msg = self:isBoughtBySelf(g)
        args = {}
        if ok then
            good = g
            break
        end
    end

    if not good then
        self:sendError(shipFaction, msg, unpack(args))
        return
    end

    -- make sure the ship can not sell more than the station can have in stock
    local maxAmountPlaceable = self:getMaxStock(good) - self:getNumGoods(good.name);

    if maxAmountPlaceable < amount then
        amount = maxAmountPlaceable

        if maxAmountPlaceable == 0 then
            self:sendError(shipFaction, "This station is not able to take any more %s."%_t, good:pluralForm(0))
        end
    end

    -- do this only for player stations
    if station.playerOrAllianceOwned then
        -- check if there is actually enough cargo space available
        -- cargo space could be filled by player with goods, that the station doesn't buy
        if station.freeCargoSpace < (amount * good.size) then
            amount = math.floor(station.freeCargoSpace / good.size)
        end
    end

    -- make sure the player does not sell more than he has in his cargo bay
    local amountOnShip = ship:getCargoAmount(good)

    if amountOnShip < amount then
        amount = amountOnShip

        if amountOnShip == 0 then
            self:sendError(shipFaction, "You don't have any %s on your ship."%_t, good:pluralForm(0))
        end
    end

    if amount <= 0 then
        return
    end

    -- begin transaction
    -- calculate price. if the seller is the owner of the station, the price is 0
    local price = self:getBuyPrice(good.name, shipFaction.index) * amount

    local canPay, msg, args = stationFaction:canPay(price * self.factionPaymentFactor);
    if not canPay then
        self:sendError(shipFaction, "This station's faction doesn't have enough money."%_t)
        return
    end

    if not noDockCheck then
        -- test the docking last so the player can know what he can buy from afar already
        local errors = {}
        errors[EntityType.Station] = "You must be docked to the station to trade."%_T
        errors[EntityType.Ship] = "You must be closer to the ship to trade."%_T
        if not CheckShipDocked(shipFaction, ship, station, errors) then
            return
        end
    end

    local x, y = Sector():getCoordinates()
    local fromDescription = Format("\\s(%1%:%2%) %3% bought %4% %5% for ¢%6%."%_T, x, y, station.name, math.floor(amount), good:pluralForm(math.floor(amount)), createMonetaryString(price))
    local toDescription = Format("\\s(%1%:%2%) %3% sold %4% %5% for ¢%6%."%_T, x, y, ship.name, math.floor(amount), good:pluralForm(math.floor(amount)), createMonetaryString(price))

    -- give money to ship faction
    self:transferMoney(stationFaction, stationFaction, shipFaction, price, fromDescription, toDescription)

    -- remove goods from ship
    ship:removeCargo(good, amount)

    if callingPlayer then
        Player(callingPlayer):sendCallback("onTradingManagerBuyFromPlayer", good.name, amount, price)
    end
    Entity():sendCallback("onTradingManagerBuyFromPlayer", good.name, amount, price)

    -- [EDE MOD] Apply tariff on cargo sale (player sells to station)
    if callingPlayer then
        edeApplyTradeTariff(shipFaction, Player(callingPlayer), price, good.name, "sale")
    end
    -- [END EDE MOD]

    -- trading (non-military) ships get higher relation gain
    local relationsChange = GetRelationChangeFromMoney(price)
    if (ship:getNumArmedTurrets()) <= 1 then
        relationsChange = relationsChange * 1.5
    end

    changeRelations(shipFaction, stationFaction, relationsChange, RelationChangeType.GoodsTrade, nil, nil, station)

    -- add goods to station, do this last so the UI update that comes with the sync already has the new relations
    self:increaseGoods(good.name, amount)
end

function TradingManager:sellToShip(shipIndex, goodName, amount, noDockCheck)
    if callingPlayer then noDockCheck = nil end

    local good = self:getSoldGoodByName(goodName)
    if good == nil then return end

    local shipFaction, ship = getInteractingFactionByShip(shipIndex, callingPlayer, AlliancePrivilege.SpendResources)
    if not shipFaction then return end

    local stationFaction = Faction()

    if self.sellToOthers == false and stationFaction.index ~= shipFaction.index then
        self:sendError(shipFaction, "This object doesn't sell goods to others."%_t)
        return
    end

    if ship.freeCargoSpace == nil then
        self:sendError(shipFaction, "Your ship has no cargo bay!"%_t)
        return
    end

    local station = Entity()

    -- check if the relations are ok
    if self.relationsThreshold and stationFaction then
        local relations = stationFaction:getRelations(shipFaction.index)
        if relations < self.relationsThreshold then
            self:sendError(shipFaction, "Relations aren't good enough to trade!"%_t)
            return
        end
    end

    -- make sure the player can not buy more than the station has in stock
    local amountBuyable = self:getNumGoods(goodName)

    if amountBuyable < amount then
        amount = amountBuyable

        if amountBuyable == 0 then
             self:sendError(shipFaction, "This station has no more %s to sell."%_t, good:pluralForm(0))
        end
    end

    -- make sure the player does not buy more than he can have in his cargo bay
    local maxShipHold = math.floor(ship.freeCargoSpace / good.size)

    if maxShipHold < amount then
        amount = maxShipHold

        if maxShipHold == 0 then
            self:sendError(shipFaction, "Your ship cannot take more %s."%_t, good:pluralForm(0))
        end
    end

    if amount <= 0 then
        return
    end

    -- begin transaction
    -- calculate price. if the owner of the station wants to buy, the price is 0
    local price = self:getSellPrice(good.name, shipFaction.index) * amount

    local canPay, msg, args = shipFaction:canPay(price);
    if not canPay then
        self:sendError(shipFaction, msg, unpack(args))
        return
    end

    if not noDockCheck then
        -- test the docking last so the player can know what he can buy from afar already
        local errors = {}
        errors[EntityType.Station] = "You must be docked to the station to trade."%_T
        errors[EntityType.Ship] = "You must be closer to the ship to trade."%_T
        if not CheckShipDocked(shipFaction, ship, station, errors) then
            return
        end
    end

    local x, y = Sector():getCoordinates()
    local fromDescription = Format("\\s(%1%:%2%) %3% bought %4% %5% for ¢%6%."%_T, x, y, ship.name, math.floor(amount), good:pluralForm(math.floor(amount)), createMonetaryString(price))
    local toDescription = Format("\\s(%1%:%2%) %3% sold %4% %5% for ¢%6%."%_T, x, y, station.name, math.floor(amount), good:pluralForm(math.floor(amount)), createMonetaryString(price))

    -- make player pay
    self:transferMoney(stationFaction, shipFaction, stationFaction, price, fromDescription, toDescription)

    -- give goods to player
    ship:addCargo(good, amount)

    if callingPlayer then
        Player(callingPlayer):sendCallback("onTradingManagerSellToPlayer", good.name, amount, price)
    end
    Entity():sendCallback("onTradingManagerSellToPlayer", good.name, amount, price)

    -- [EDE MOD] Apply tariff on cargo purchase (player buys from station)
    if callingPlayer then
        edeApplyTradeTariff(shipFaction, Player(callingPlayer), price, good.name, "purchase")
    end
    -- [END EDE MOD]

    -- trading (non-military) ships get higher relation gain
    local relationsChange = GetRelationChangeFromMoney(price)
    if (ship:getNumArmedTurrets()) <= 1 then
        relationsChange = relationsChange * 1.5
    end

    changeRelations(shipFaction, stationFaction, relationsChange, RelationChangeType.GoodsTrade, nil, nil, station)

    -- remove goods from station, do this last so the UI update that comes with the sync already has the new relations
    self:decreaseGoods(good.name, amount)

end

-- convenience function for buying goods from another faction, meant to be called from external. They're not removed from another ship, they just appear
function TradingManager:buyGoods(good, amount, otherFactionIndex, monetaryTransactionOnly)

    -- check if the good is even bought by the station
    if not self:getBoughtGoodByName(good.name) == nil then return 1 end

    local stationFaction = Faction()
    if not stationFaction then return 5 end

    local otherFaction = Faction(otherFactionIndex)
    if not otherFaction then return 5 end

    if self.buyFromOthers == false and stationFaction.index ~= otherFaction.index then return 4 end

    local ok = self:isBoughtBySelf(good)
    if not ok then return 4 end

    -- make sure the transaction can not sell more than the station can have in stock
    local buyable = self:getMaxStock(good) - self:getNumGoods(good.name);
    amount = math.min(buyable, amount)
    if amount <= 0 then return 2 end

    -- begin transaction
    -- calculate price. if the seller is the owner of the station, the price is 0
    local price = self:getBuyPrice(good.name, otherFactionIndex) * amount

    local canPay, msg, args = stationFaction:canPay(price * self.factionPaymentFactor);
    if not canPay then return 3 end

    local x, y = Sector():getCoordinates()
    local fromDescription = Format("\\s(%1%:%2%) %3% bought %4% %5% for ¢%6%."%_T, x, y, Entity().name, math.floor(amount), good:pluralForm(math.floor(amount)), createMonetaryString(price))
    local toDescription = Format("\\s(%1%:%2%): Sold %3% %4% for ¢%5%."%_T, x, y, math.floor(amount), good:pluralForm(math.floor(amount)), createMonetaryString(price))

    -- give money to other faction
    self:transferMoney(stationFaction, stationFaction, otherFaction, price, fromDescription, toDescription)

    local relationsChange = GetRelationChangeFromMoney(price)
    changeRelations(otherFaction, stationFaction, relationsChange, RelationChangeType.GoodsTrade, nil, nil, Entity())

    if not monetaryTransactionOnly then
        -- add goods to station, do this last so the UI update that comes with the sync already has the new relations
        self:increaseGoods(good.name, amount)
    end

    return 0, price
end

-- convenience function for selling goods to another faction. They're not added to another ship, they just disappear
function TradingManager:sellGoods(good, amount, otherFactionIndex, monetaryTransactionOnly)

    local stationFaction = Faction()
    if not stationFaction then return 5 end

    local otherFaction = Faction(otherFactionIndex)
    if not otherFaction then return 5 end

    if self.sellToOthers == false and stationFaction.index ~= otherFaction.index then
        return 4
    end

    local sellable = self:getNumGoods(good.name)
    amount = math.min(sellable, amount)
    if amount <= 0 then return 1 end

    local price = self:getSellPrice(good.name, otherFactionIndex) * amount
    local canPay = otherFaction:canPay(price);
    if not canPay then return 2 end

    local x, y = Sector():getCoordinates()
    local toDescription = Format("\\s(%1%:%2%) %3% sold %4% %5% for ¢%6%."%_T, x, y, Entity().name, math.floor(amount), good:pluralForm(math.floor(amount)), createMonetaryString(price))
    local fromDescription = Format("\\s(%1%:%2%): Bought %3% %4% for ¢%5%."%_T, x, y, math.floor(amount), good:pluralForm(math.floor(amount)), createMonetaryString(price))

    -- make other faction pay
    self:transferMoney(stationFaction, otherFaction, stationFaction, price, fromDescription, toDescription)

    local relationsChange = GetRelationChangeFromMoney(price)
    changeRelations(otherFaction, stationFaction, relationsChange, RelationChangeType.GoodsTrade, nil, nil, Entity())

    if not monetaryTransactionOnly then
        -- remove goods from station, do this last so the UI update that comes with the sync already has the new relations
        self:decreaseGoods(good.name, amount)
    end

    return 0, price
end

function TradingManager:increaseGoods(name, delta)

    local entity = Entity()
    local added = false

    for i, good in pairs(self.soldGoods) do
        if good.name == name then
            -- increase
            local current = entity:getCargoAmount(good)
            delta = math.min(delta, self:getMaxStock(good) - current)
            delta = math.max(delta, 0)

            if not added then
                entity:addCargo(good, delta)
                added = true
            end

            broadcastInvokeClientFunction("updateSoldGoodAmount", good.name)
        end
    end

    for i, good in pairs(self.boughtGoods) do
        if good.name == name then
            -- increase
            local current = entity:getCargoAmount(good)
            delta = math.min(delta, self:getMaxStock(good) - current)
            delta = math.max(delta, 0)

            if not added then
                entity:addCargo(good, delta)
                added = true
            end

            broadcastInvokeClientFunction("updateBoughtGoodAmount", good.name)
        end
    end

end

function TradingManager:decreaseGoods(name, amount)

    local entity = Entity()
    local removed = false

    for i, good in pairs(self.soldGoods) do
        if good.name == name then
            if not removed then
                entity:removeCargo(good, amount)
                removed = true
            end

            broadcastInvokeClientFunction("updateSoldGoodAmount", good.name)
        end
    end

    for i, good in pairs(self.boughtGoods) do
        if good.name == name then
            if not removed then
                entity:removeCargo(good, amount)
                removed = true
            end

            broadcastInvokeClientFunction("updateBoughtGoodAmount", good.name)
        end
    end

    return removed
end

function TradingManager:useUpBoughtGoods(timeStep)

    if not self.useUpGoodsEnabled then return end

    local tickTime = 120

    self.useTimeCounter = self.useTimeCounter + timeStep
    if self.useTimeCounter > tickTime then
        self.useTimeCounter = self.useTimeCounter - tickTime

        for i = 1, 5 do
            local amount = math.random(10, 60)
            local good = self.boughtGoods[math.random(1, #self.boughtGoods)]

            if not good then goto continue end

            local inStock = self:getNumGoods(good.name)
            amount = math.min(inStock, amount)

            if amount == 0 then goto continue end

            self:decreaseGoods(good.name, amount)

            local faction = Faction()
            if faction then
                local station = Entity()
                local price = self:getBuyPrice(good.name)
                local received = price * 1.10 * amount

                local x, y = Sector():getCoordinates()
                local description = Format("\\s(%1%:%2%) %3%'s population consumed %4% %5% and paid you ¢%6% for it (¢%7% profit)."%_T,
                                                x, y,
                                                station.name,
                                                math.floor(amount),
                                                good:pluralForm(math.floor(amount)),
                                                createMonetaryString(received),
                                                createMonetaryString(price * amount * 0.10))

                faction:receive(description, received)
                self.stats.moneyGainedFromGoods = self.stats.moneyGainedFromGoods + received
            end

            break

            ::continue::
        end
    end

end

function TradingManager:getBoughtGoods()
    local result = {}

    for i, good in pairs(self.boughtGoods) do
        table.insert(result, good.name)
    end

    return unpack(result)
end

function TradingManager:getSoldGoods()
    local result = {}

    for i, good in pairs(self.soldGoods) do
        table.insert(result, good.name)
    end

    return unpack(result)
end

function TradingManager:getStock(name)
    return self:getNumGoods(name), self:getMaxGoods(name)
end

function TradingManager:getNumGoods(name)
    local entity = Entity()

    local g = goods[name]
    if not g then return 0 end

    local good = g:good()
    if not good then return 0 end

    local amount = entity:getCargoAmount(good)
    return amount
end

function TradingManager:getMaxGoods(name)
    local amount = 0

    for i, good in pairs(self.soldGoods) do
        if good.name == name then
            return self:getMaxStock(good)
        end
    end

    for i, good in pairs(self.boughtGoods) do
        if good.name == name then
            return self:getMaxStock(good)
        end
    end

    return amount
end

function TradingManager:getGoodSize(name)

    for i, good in pairs(self.soldGoods) do
        if good.name == name then
            return good.size
        end
    end

    for i, good in pairs(self.boughtGoods) do
        if good.name == name then
            return good.size
        end
    end

    print ("error: " .. name .. " is neither bought nor sold")
end

function TradingManager:getMaxStock(good)
    local entity = Entity()

    local space = entity.maxCargoSpace
    local slots = self.numBought + self.numSold

    if slots > 0 then space = space / slots end

    local goodSize = good.size
    if space / goodSize > 100 then
        -- round to 100
        return math.min(50000, round(space / goodSize / 100) * 100)
    else
        -- not very much space already, don't round
        return math.floor(space / goodSize)
    end
end

function TradingManager:getBoughtGoodByName(name)
    for _, good in pairs(self.boughtGoods) do
        if good.name == name then
            return good
        end
    end
end

function TradingManager:getSoldGoodByName(name)
    for _, good in pairs(self.soldGoods) do
        if good.name == name then
            return good
        end
    end
end

function TradingManager:getGoodByName(name)
    for _, good in pairs(self.boughtGoods) do
        if good.name == name then
            return good
        end
    end

    for _, good in pairs(self.soldGoods) do
        if good.name == name then
            return good
        end
    end
end

-- price for which goods are bought by this from others
function TradingManager:getBuyPrice(goodName, sellingFactionIndex)

    local good = self:getBoughtGoodByName(goodName)
    if not good then return 0 end

    -- this is to ensure that goods can be "taken" from consumers via the buy sell UI
    -- instead of using transfer cargo UI
    if self.factionPaymentFactor == 0 and sellingFactionIndex then
        local stationFaction = Faction()

        if not stationFaction or stationFaction.index == sellingFactionIndex then return 0 end

        if stationFaction.isAlliance then
            -- is the selling player a member of the station alliance?
            local seller = Player(sellingFactionIndex)
            if seller and seller.allianceIndex == stationFaction.index then return 0 end
        end

        if stationFaction.isPlayer then
            -- does the station belong to a player that is a member of the ship's alliance?
            local stationPlayer = Player(stationFaction.index)
            if stationPlayer and stationPlayer.allianceIndex == sellingFactionIndex then return 0 end
        end
    end

    -- better relations -> lower price
    -- worse relations -> (much) higher price
    local relationFactor = 1
    if sellingFactionIndex then
        local sellerIndex = nil
        if type(sellingFactionIndex) == "number" then
            sellerIndex = sellingFactionIndex
        else
            sellerIndex = sellingFactionIndex.index
        end

        if sellerIndex then
            local faction = Faction()
            if faction then
                if faction.isAIFaction then
                    local relations = faction:getRelations(sellerIndex)
                    if relations < -10000 then
                        -- bad relations: faction pays less for the goods
                        -- 10% to 100% from -100.000 to -10.000
                        relationFactor = lerp(relations, -100000, -10000, 0.1, 1.0)
                    elseif relations >= 80000 then
                        -- very good relations: factions pays MORE for the goods
                        -- 100% to 105% from 80.000 to 100.000
                        relationFactor = lerp(relations, 80000, 100000, 1.0, 1.05)
                    end
                end

                if Faction().index == sellerIndex then relationFactor = 0 end
            end
        end
    end

    -- get factor for supply/demand from supply/demand script
    local ok, supplyDemandFactor = Sector():invokeFunction("economyupdater.lua", "getSupplyDemandPriceChange", good.name, self.ownSupplyTypes[good.name])
    if ok ~= 0 then
--        eprint("buy price: error getting supply demand factor: " .. tostring(ok))
    end

    supplyDemandFactor = supplyDemandFactor or 0
    supplyDemandFactor = 1 + (supplyDemandFactor * self.supplyDemandInfluence)

    local basePrice = round(good.price * self.buyPriceFactor)
    local price = round(good.price * supplyDemandFactor * relationFactor * self.buyPriceFactor)

    return price, basePrice, supplyDemandFactor, relationFactor, self.buyPriceFactor
end

-- price for which goods are sold from this to others
function TradingManager:getSellPrice(goodName, buyingFaction)

    local good = self:getSoldGoodByName(goodName)
    if not good then return 0 end

    local relationFactor = 1
    if buyingFaction then
        local sellerIndex = nil
        if type(buyingFaction) == "number" then
            sellerIndex = buyingFaction
        else
            sellerIndex = buyingFaction.index
        end

        if sellerIndex then
            local faction = Faction()
            if faction then
                if faction.isAIFaction then
                    local relations = faction:getRelations(sellerIndex)
                    if relations < -10000 then
                        -- bad relations: faction wants more for the goods
                        -- 200% to 100% from -100.000 to -10.000
                        relationFactor = lerp(relations, -100000, -10000, 2.0, 1.0)
                    elseif relations > 80000 then
                        -- good relations: factions start giving player better prices
                        -- 100% to 95% from 80.000 to 100.000
                        relationFactor = lerp(relations, 80000, 100000, 1.0, 0.95)
                    end
                end

                if faction.index == sellerIndex then relationFactor = 0 end
            end
        end
    end

    -- get factor for supply/demand from supply/demand script
    local ok, supplyDemandFactor = Sector():invokeFunction("economyupdater.lua", "getSupplyDemandPriceChange", good.name, self.ownSupplyTypes[good.name])
    if ok ~= 0 then
        -- eprint("sell price: error getting supply demand factor: " .. tostring(ok))
    end

    supplyDemandFactor = supplyDemandFactor or 0
    supplyDemandFactor = 1 + (supplyDemandFactor * self.supplyDemandInfluence)

    local basePrice = round(good.price * self.sellPriceFactor)
    local price = round(good.price * supplyDemandFactor * relationFactor * self.sellPriceFactor)

    return price, basePrice, supplyDemandFactor, relationFactor, self.sellPriceFactor
end


local r = Random(Seed(os.time()))

local organizeUpdateFrequency
local organizeUpdateTime

function organizePhrase()
    local phrases = {
        "Hey, I am planning a birthday party. I need a little bit of help with acquiring some goods. I can't buy them by myself, because that would kill the surprise."%_T,
        "My experiments need new ingredients. I need some goods as soon as possible, before someone finds out about my secrets."%_T,
        "I need some goods. Help me get them without my name being directly involved."%_T,
        "Could somebody bring me new stuff? I am scared of all the people around here so I can't get it by myself. I will pay a good price for the delivery"%_T,
        }

    local rand = r:getInt(1, #phrases)
    local phrase = phrases[rand]

    return phrase
end
local organizeDescription = [[
${introPhrase}

Procure ${amount} ${displayName} in 30 minutes.

You will be paid four times the usual price, plus a bonus.

Time Limit: 30 minutes
Reward: ¢${reward}]]%_t

function TradingManager:updateOrganizeGoodsBulletins(timeStep)

    if not organizeUpdateFrequency then
        -- more frequent updates when there are more ingredients
        organizeUpdateFrequency = math.max(60 * 8, 60 * 60 - (#self.boughtGoods * 7.5 * 60))
    end

    if not organizeUpdateTime then
        -- by adding half the time here, we have a chance that a factory immediately has a bulletin
        organizeUpdateTime = 0

        local minutesSimulated = r:getInt(10, 80)
        for i = 1, minutesSimulated do -- simulate bulletin posting / removing
            self:updateOrganizeGoodsBulletins(60)
        end
    end

    organizeUpdateTime = organizeUpdateTime + timeStep

    -- don't execute the following code if the time hasn't exceeded the posting frequency
    if organizeUpdateTime < organizeUpdateFrequency then return end
    organizeUpdateTime = organizeUpdateTime - organizeUpdateFrequency

    -- choose a random ingredient
    local good = self.boughtGoods[r:getInt(1, #self.boughtGoods)]
    if not good then return end

    local x, y = Sector():getCoordinates()
    local maxWorth = 20000 * Balancing_GetSectorRichnessFactor(x, y)

    local volume = random():getInt(100, 250)
    local amount = math.min(math.floor(volume / good.size), 150)
    amount = math.ceil(math.min(amount, maxWorth / good.price))

    local goodSold
    for k, soldGood in pairs(self.soldGoods) do
        if soldGood == good then
            if self:getNumGoods(soldGood.name) >= amount then
                return
            end
        end
    end

    local reward = good.price * amount * 4.0 + maxWorth

    local bulletin =
    {
        brief = "Resource Shortage: ${amount} ${displayName}"%_T,
        description = organizeDescription,
        difficulty = "Easy /*difficulty*/"%_T,
        reward = string.format("¢${reward}"%_T, createMonetaryString(reward)),
        script = "missions/organizegoods.lua",
        arguments = {good.name, amount, Entity().index, x, y, reward},
        formatArguments = {amount = amount, displayName = good:pluralForm(amount), reward = createMonetaryString(reward), introPhrase = PluralForm(organizePhrase())}
    }

    -- since in this case "add" can override "remove", adding a bulletin is slightly more probable
    local add = r:getFloat() < 0.5
    local remove = r:getFloat() < 0.5

    if not add and not remove then
        if r:getFloat() < 0.5 then
            add = true
        else
            remove = true
        end
    end

    if add then
        -- randomly add bulletins
        Entity():invokeFunction("bulletinboard", "postBulletin", bulletin)
    elseif remove then
        -- randomly remove bulletins
        Entity():invokeFunction("bulletinboard", "removeBulletin", bulletin.brief)
    end

end

local deliveryDescription = [[
Deliver ${amount} ${displayName} to a station near this location in 20 minutes.

You will need ${cargoSpace} free cargo space to take in the goods.

You will have to make a deposit of ¢${deposit}, which will be reimbursed upon delivery of the goods.

Deposit: ¢${deposit}
Time Limit: 20 minutes
Reward: ¢${reward}]]%_t

local deliveryUpdateFrequency
local deliveryUpdateTime

function TradingManager:updateDeliveryBulletins(timeStep)

    if not deliveryUpdateFrequency then
        -- more frequent updates when there are more ingredients
        deliveryUpdateFrequency = math.max(60 * 8, 60 * 60 - (#self.soldGoods * 7.5 * 60))
    end

    if not deliveryUpdateTime then
        -- by adding half the time here, we have a chance that a factory immediately has a bulletin
        deliveryUpdateTime = 0

        local minutesSimulated = r:getInt(10, 80)
        for i = 1, minutesSimulated do -- simulate 1 hour of bulletin posting / removing
            self:updateDeliveryBulletins(60)
        end
    end

    deliveryUpdateTime = deliveryUpdateTime + timeStep

    -- don't execute the following code if the time hasn't exceeded the posting frequency
    if deliveryUpdateTime < deliveryUpdateFrequency then return end
    deliveryUpdateTime = deliveryUpdateTime - deliveryUpdateFrequency

    -- choose a sold good
    local good = self.soldGoods[r:getInt(1, #self.soldGoods)]
    if not good then return end
    if good.dangerous then return end
    if good.illegal then return end

    local cargoVolume = 50 + r:getFloat(0, 200)
    local amount = math.min(math.floor(cargoVolume / good.size), 150)
    local reward = good.price * amount
    local x, y = Sector():getCoordinates()

    -- add a maximum of earnable money
    local maxEarnable = 20000 * Balancing_GetSectorRichnessFactor(x, y)
    if reward > maxEarnable then
        amount = math.floor(maxEarnable / good.price)
        reward = good.price * amount
    end

    if amount == 0 then return end

    local cargoSpace = math.ceil(amount * good.size)
    reward = reward + 5000 * Balancing_GetSectorRichnessFactor(x, y)
    local deposit = math.floor(good.price * amount * 0.75 / 100) * 100
    local reward = math.floor(reward / 100) * 100

    -- todo: localization of entity titles
    local bulletin =
    {
        brief = "Delivery: ${displayName}"%_T,
        description = deliveryDescription,
        difficulty = "Easy"%_T,
        reward = string.format("¢%s"%_T, createMonetaryString(reward)),
        formatArguments = {displayName = good:pluralForm(amount), amount = amount, cargoSpace = cargoSpace, deposit = createMonetaryString(deposit), reward = createMonetaryString(reward)},

        script = "missions/delivery.lua",
        arguments = {good.name, amount, Entity().index, deposit + reward},

        checkAccept = [[
            local self, player = ...
            local ship = Entity(player.craftIndex)
            local shipFaction = Faction(ship.factionIndex)
            local space = ship.freeCargoSpace or 0
            if space < self.good.size * self.amount then
                player:sendChatMessage(self.sender, 1, self.msgCargo)
                return 0
            end
            local canPay = shipFaction:canPay(self.deposit)
            if not canPay then
                player:sendChatMessage(self.sender, 1, self.msgMoney)
                return 0
            end
            if not Entity():isInDockingArea(ship) then
                player:sendChatMessage(self.sender, 1, self.msgDock)
                return 0
            end
            return 1
            ]],
        onAccept = [[
            local self, player = ...
            local ship = Entity(player.craftIndex)
            local shipFaction = Faction(ship.factionIndex)
            shipFaction:pay(self.deposit)
            ship:addCargo(goods[self.good.name]:good(), self.amount)
            ]],

        cargoVolume = cargoVolume,
        amount = amount,
        good = good,
        deposit = deposit,
        sender = "Client"%_T,
        msgCargo = "Not enough cargo space on your ship."%_T,
        msgDock = "You have to be docked to the station."%_T,
        msgMoney = "You don't have enough money for the deposit."%_T
    }

    -- since in this case "add" can override "remove", adding a bulletin is slightly more probable
    local add = r:getFloat() < 0.5
    local remove = r:getFloat() < 0.5

    if not add and not remove then
        if r:getFloat() < 0.5 then
            add = true
        else
            remove = true
        end
    end

    if add then
        -- randomly add bulletins
        Entity():invokeFunction("bulletinboard", "postBulletin", bulletin)
    elseif remove then
        -- randomly remove bulletins
        Entity():invokeFunction("bulletinboard", "removeBulletin", bulletin.brief)
    end

end

function TradingManager:getBuyGoodsErrorMessage(code)
    if code == 0 then
        return "No error."%_T
    elseif code == 1 then
        return "Good isn't bought."%_T
    elseif code == 2 then
        return "No more space."%_T
    elseif code == 3 then
        return "Not enough money."%_T
    elseif code == 4 then
        return "Good isn't bought."%_T
    end

    return "Unknown error."%_T
end

function TradingManager:getSellGoodsErrorMessage(code)
    if code == 0 then
        return "No error."%_T
    elseif code == 1 then
        return "No more goods."%_T
    elseif code == 2 then
        return "Not enough money."%_T
    end

    return "Unknown error."%_T
end

function TradingManager:getTax()
    return self.tax
end

function TradingManager:getFactionPaymentFactor()
    return self.factionPaymentFactor
end

function TradingManager:reportError(msg)
    print (msg)

    local info = DebugInfo()
    info:threadSet("TradingManager received goods", tostring(self.receivedGoods))
    info:threadSet("TradingManager bought goods", enumerate(self.boughtGoods, function(g) return g.name end))
    info:threadSet("TradingManager sold goods", enumerate(self.soldGoods, function(g) return g.name end))
    info:threadSet("TradingManager title", Entity().title)

    reportError(msg)
end

PublicNamespace.CreateTradingManager = setmetatable({new = new}, {__call = function(_, ...) return new(...) end})

function PublicNamespace.CreateTabbedWindow(caption)
    local menu = ScriptUI()

    if not PublicNamespace.tabbedWindow then
        local res = getResolution()
        local size = vec2(950, 650)

        local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5));

        window.caption = caption or ""
        window.showCloseButton = 1
        window.moveable = 1

        -- create a tabbed window inside the main window
        PublicNamespace.tabbedWindow = window:createTabbedWindow(Rect(vec2(10, 10), size - 10))
        PublicNamespace.window = window
    end

    -- registers the window for this script, enabling the default window interaction calls like onShowWindow(), renderUI(), etc.
    -- if the same window is registered more than once, an interaction option will only be shown for the first registration
    menu:registerWindow(PublicNamespace.window, "Trade Goods"%_t, 5);

    return PublicNamespace.tabbedWindow
end

function PublicNamespace.CreateNamespace()
    local result = {}

    local trader = PublicNamespace.CreateTradingManager()
    result.trader = trader
    result.updateDeliveryBulletins = function(...) return trader:updateDeliveryBulletins(...) end
    result.updateOrganizeGoodsBulletins = function(...) return trader:updateOrganizeGoodsBulletins(...) end
    result.getSellPrice = function(...) return trader:getSellPrice(...) end
    result.getBuyPrice = function(...) return trader:getBuyPrice(...) end
    result.getGoodByName = function(...) return trader:getGoodByName(...) end
    result.getSoldGoodByName = function(...) return trader:getSoldGoodByName(...) end
    result.getBoughtGoodByName = function(...) return trader:getBoughtGoodByName(...) end
    result.getMaxStock = function(...) return trader:getMaxStock(...) end
    result.getGoodSize = function(...) return trader:getGoodSize(...) end
    result.getMaxGoods = function(...) return trader:getMaxGoods(...) end
    result.getNumGoods = function(...) return trader:getNumGoods(...) end
    result.getStock = function(...) return trader:getStock(...) end
    result.getSoldGoods = function(...) return trader:getSoldGoods(...) end
    result.getBoughtGoods = function(...) return trader:getBoughtGoods(...) end
    result.getBuyPriceFactor = function(...) return trader.buyPriceFactor end
    result.getSellPriceFactor = function(...) return trader.sellPriceFactor end
    result.setBuyPriceFactor = function(...) return trader:setBuyPriceFactor(...) end
    result.setSellPriceFactor = function(...) return trader:setSellPriceFactor(...) end
    result.useUpBoughtGoods = function(...) return trader:useUpBoughtGoods(...) end
    result.decreaseGoods = function(...) return trader:decreaseGoods(...) end
    result.increaseGoods = function(...) return trader:increaseGoods(...) end
    result.sellToShip = function(...) return trader:sellToShip(...) end
    result.buyFromShip = function(...) return trader:buyFromShip(...) end
    result.onSellButtonPressed = function(...) return trader:onSellButtonPressed(...) end
    result.onBuyButtonPressed = function(...) return trader:onBuyButtonPressed(...) end
    result.onSellTextEntered = function(...) return trader:onSellTextEntered(...) end
    result.onBuyTextEntered = function(...) return trader:onBuyTextEntered(...) end
    result.buildGui = function(...) return trader:buildGui(...) end
    result.buildSellGui = function(...) return trader:buildSellGui(...) end
    result.buildBuyGui = function(...) return trader:buildBuyGui(...) end
    result.updateSoldGoodAmount = function(...) return trader:updateSoldGoodAmount(...) end
    result.updateBoughtGoodAmount = function(...) return trader:updateBoughtGoodAmount(...) end
    result.receiveGoods = function(...) return trader:receiveGoods(...) end
    result.sendGoods = function(...) return trader:sendGoods(...) end
    result.requestGoods = function(...) return trader:requestGoods(...) end
    result.initializeTrading = function(...) return trader:initializeTrading(...) end
    result.getInitialGoods = function(...) return trader:getInitialGoods(...) end
    result.simulatePassedTime = function(...) return trader:simulatePassedTime(...) end

    result.secureTradingGoods = function(...) return trader:secureTradingGoods(...) end
    result.restoreTradingGoods = function(...) return trader:restoreTradingGoods(...) end
    result.sendError = function(...) return trader:sendError(...) end
    result.buyGoods = function(...) return trader:buyGoods(...) end
    result.sellGoods = function(...) return trader:sellGoods(...) end
    result.getBuysFromOthers = function(...) return trader:getBuysFromOthers(...) end
    result.getSellsToOthers = function(...) return trader:getSellsToOthers(...) end
    result.setBuysFromOthers = function(...) return trader:setBuysFromOthers(...) end
    result.setSellsToOthers = function(...) return trader:setSellsToOthers(...) end

    result.setUseUpGoodsEnabled = function(enabled) trader.useUpGoodsEnabled = enabled end
    result.getBuyGoodsErrorMessage = function(enabled) trader.getBuyGoodsErrorMessage = enabled end
    result.getSellGoodsErrorMessage = function(enabled) trader.getSellGoodsErrorMessage = enabled end
    result.getTax = function() return trader:getTax() end
    result.getFactionPaymentFactor = function() return trader:getFactionPaymentFactor() end

    -- the following comment is important for a unit test
    -- Dynamic Namespace result
    callable(result, "sendGoods")
    callable(result, "sellToShip")
    callable(result, "buyFromShip")

    return result
end

return PublicNamespace
