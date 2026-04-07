package.path = package.path .. ";data/scripts/lib/?.lua"
include ("randomext")
include ("galaxy")
include ("utility")
include ("stringutility")
include ("faction")
include ("player")
include ("relations")
include ("merchantutility")
include ("callable")
local Dialog = include("dialogutility")

-- [EDE MOD] Tariff/agreement hooks for resource trades
-- Lazy-load to avoid interfering with ResourceDepot's own loading
local edeTariffManager = nil
local edeAgreementManager = nil

local function edeGetModules()
    if not edeTariffManager then
        edeTariffManager = include("diplomacy/tariff_manager")
        edeAgreementManager = include("diplomacy/agreement_manager")
    end
    return edeTariffManager, edeAgreementManager
end

local function edeApplyTradeTariff(playerFaction, player, price, materialName, tradeDirection)
    if not playerFaction or not player or price <= 0 then return end
    local station = Entity()
    if not station then return end
    local stationFactionIndex = station.factionIndex
    local store = Server()

    local TM, AM = edeGetModules()
    if not TM or not AM then return end

    local surcharge, tariff_rate = TM.calculateSurcharge(
        store, stationFactionIndex, playerFaction.index, price)
    local _, agreement_rate = AM.calculateDiscount(
        store, playerFaction.index, stationFactionIndex, price)

    local net = surcharge
    if agreement_rate > 0 then
        net = net - math.floor(price * agreement_rate + 0.5)
    end

    if net > 0 then
        if playerFaction:canPayMoney(net) then
            playerFaction:pay("Tariff surcharge", net)
            local tariff = TM.get(store, stationFactionIndex, playerFaction.index)
                or TM.get(store, playerFaction.index, stationFactionIndex)
            if tariff and tariff.imposer then
                local imposer = Faction(tariff.imposer)
                if imposer then imposer:receive("Tariff revenue", net) end
                TM.recordRevenue(store, tariff.imposer, tariff.target, net)
            end
            player:sendChatMessage("EDE", ChatMessageType.Normal,
                string.format("Tariff: -%s cr (%d%% on %s of %s)",
                    tostring(net), math.floor(tariff_rate * 100), tradeDirection, materialName))
        end
    elseif net < 0 then
        local bonus = math.abs(net)
        playerFaction:receive("Trade agreement discount", bonus)
        player:sendChatMessage("EDE", ChatMessageType.Normal,
            string.format("Trade discount: +%s cr (%d%% on %s of %s)",
                tostring(bonus), math.floor(agreement_rate * 100), tradeDirection, materialName))
    end
end
-- [END EDE MOD]

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace ResourceDepot
ResourceDepot = {}

ResourceDepot.interactionThreshold = -80000
ResourceDepot.fixedBuyRatio = nil
ResourceDepot.fixedSellRatio = nil



-- Menu items
local window = 0
local buyAmountTextBox = 0
local sellAmountTextBox = 0

local stock = {}
local buyPrice = {}
local sellPrice = {}

local soldGoodStockLabels = {}
local soldGoodPriceLabels = {}
local soldGoodTextBoxes = {}
local soldGoodButtons = {}

local boughtGoodNameLabels = {}
local boughtGoodStockLabels = {}
local boughtGoodPriceLabels = {}
local boughtGoodTextBoxes = {}
local boughtGoodButtons = {}

local shortageMaterial
local shortageAmount
local shortageTimer

local guiInitialized = false

-- if this function returns false, the script will not be listed in the interaction window,
-- even though its UI may be registered
function ResourceDepot.interactionPossible(playerIndex, option)
    return CheckFactionInteraction(playerIndex, ResourceDepot.interactionThreshold)
end

function ResourceDepot.getUpdateInterval()
    return 60
end

function ResourceDepot.restore(data)
    stock = data

    -- keep compatibility with old saves
    if tablelength(stock) == 10 then
        shortageMaterial = table.remove(stock, 8)
        shortageAmount = table.remove(stock, 8)
        shortageTimer = table.remove(stock, 8)

        if shortageMaterial == -1 then shortageMaterial = nil end
        if shortageAmount == -1 then shortageAmount = nil end
    end

    if shortageTimer == nil then
        shortageTimer = -random():getInt(15 * 60, 60 * 60)
    elseif shortageTimer >= 0 and shortageMaterial ~= nil then
        ResourceDepot.startShortage()
    end
end

function ResourceDepot.secure()
    data = {}
    for k, v in pairs(stock) do
        table.insert(data, k, v)
    end

    table.insert(data, shortageMaterial or -1)
    table.insert(data, shortageAmount or -1)
    table.insert(data, shortageTimer)

    return data
end

function ResourceDepot.initialize()

    local station = Entity()
    if station.title == "" then
        station.title = "Resource Depot"%_t
    end

    for i = 1, NumMaterials() do
        sellPrice[i] = 10 * Material(i - 1).costFactor
        buyPrice[i] = 10 * Material(i - 1).costFactor
    end

    if onServer() then
        math.randomseed(Sector().seed + Sector().numEntities)

        stock = ResourceDepot.getInitialResources()

        -- resource shortage
        shortageTimer = -random():getInt(15 * 60, 60 * 60)

        math.randomseed(appTimeMs())

        local faction = Faction()
        if faction and faction.isAIFaction then
            Sector():registerCallback("onRestoredFromDisk", "onRestoredFromDisk")
        end
    end

    if onClient() and EntityIcon().icon == "" then
        EntityIcon().icon = "data/textures/icons/pixel/resources.png"
        InteractionText(station.index).text = Dialog.generateStationInteractionText(station, random())
    end

    if station.type == EntityType.Station then
        station:addScriptOnce("data/scripts/entity/merchants/refinery.lua")
    end

    station:addScriptOnce("data/scripts/entity/merchants/resourcedepotbuildingknowledgemerchant.lua")
end

function ResourceDepot.onRestoredFromDisk(timeSinceLastSimulation)
    ResourceDepot.updateServer(timeSinceLastSimulation)

    local factor = math.max(0, math.min(1, (timeSinceLastSimulation - 20 * 60) / (2 * 60 * 60)))
    local newStock = ResourceDepot.getInitialResources()

    for i, amount in pairs(newStock) do
        local diff = math.floor((amount - stock[i]) * factor)

        if diff ~= 0 then
            stock[i] = stock[i] + diff
            broadcastInvokeClientFunction("setData", i, stock[i])
        end
    end
end

function ResourceDepot.getInitialResources()
    local amounts = {}

    local x, y = Sector():getCoordinates()
    local probabilities = Balancing_GetMaterialProbability(x, y)

    for i = 1, NumMaterials() do
        amounts[i] = math.max(0, probabilities[i - 1] - 0.1) * (getInt(45000, 65000) * Balancing_GetSectorRichnessFactor(x, y))
    end

    local num = 0
    for i = NumMaterials(), 1, -1 do
        amounts[i] = amounts[i] + num
        num = num + amounts[i] / 4
    end

    for i = 1, NumMaterials() do
        amounts[i] = round(amounts[i])
    end

    return amounts
end

-- create all required UI elements for the client side
function ResourceDepot.initUI()
    local res = getResolution()
    local size = vec2(700, 335)

    local menu = ScriptUI()
    window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5));
    menu:registerWindow(window, "Trade Resources"%_t, 10);

    local station = Entity()
    window.caption = station.translatedTitle
    window.showCloseButton = 1
    window.moveable = 1

    -- create a tabbed window inside the main window
    local tabbedWindow = window:createTabbedWindow(Rect(vec2(10, 10), size - 10))

    -- create buy tab
    local buyTab = tabbedWindow:createTab("Buy"%_t, "data/textures/icons/bag.png", "Buy from station"%_t)
    ResourceDepot.buildBuyGui(buyTab)

    -- create sell tab
    local sellTab = tabbedWindow:createTab("Sell"%_t, "data/textures/icons/sell.png", "Sell to station"%_t)
    ResourceDepot.buildSellGui(sellTab)

    ResourceDepot.retrieveData();

    guiInitialized = true

end

function ResourceDepot.initializationFinished()
    -- use the initilizationFinished() function on the client since in initialize() we may not be able to access Sector scripts on the client
    if onClient() then
        local ok, r = Sector():invokeFunction("radiochatter", "addSpecificLines", Entity().id.string,
        {
            "Occupy cash register ${N3} please."%_t,
            "This is where you get the stuff ships are made from."%_t,
            "Extract resources from scrap and ores here!"%_t,
            "We're offering high-quality resources for your ship building needs."%_t,
            "No cash but tons of resources? Sell us your resources. Best price in the sector!"%_t,
            "No resources but tons of cash? Buy our resources. Best price in the sector!"%_t,
        })
    end
end

function ResourceDepot.buildBuyGui(window)
    ResourceDepot.buildGui(window, 1)
end

function ResourceDepot.buildSellGui(window)
    ResourceDepot.buildGui(window, 0)
end

function ResourceDepot.buildGui(window, guiType)

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

    local nameX = 10
    local stockX = 250
    local volX = 340
    local priceX = 390
    local textBoxX = 480
    local buttonX = 550

    -- header
    -- createLabel(window, vec2(nameX, 10), "Name", 15)
    window:createLabel(vec2(stockX, 0), "STOCK"%_t, 15)
    window:createLabel(vec2(priceX, 0), "¢", 15)

    local y = 25
    for i = 1, NumMaterials() do

        local yText = y + 6

        local frame = window:createFrame(Rect(0, y, textBoxX - 10, 30 + y))

        local nameLabel = window:createLabel(vec2(nameX, yText), "", 15)
        local stockLabel = window:createLabel(vec2(stockX, yText), "", 15)
        local priceLabel = window:createLabel(vec2(priceX, yText), "", 15)
        local numberTextBox = window:createTextBox(Rect(textBoxX, yText - 6, 60 + textBoxX, 30 + yText - 6), textCallback)
        local button = window:createButton(Rect(buttonX, yText - 6, window.size.x, 30 + yText - 6), buttonCaption, buttonCallback)

        button.maxTextSize = 16

        numberTextBox.text = "0"
        numberTextBox.allowedCharacters = "0123456789"
        numberTextBox.clearOnClick = 1

        if guiType == 1 then
            table.insert(soldGoodStockLabels, stockLabel)
            table.insert(soldGoodPriceLabels, priceLabel)
            table.insert(soldGoodTextBoxes, numberTextBox)
            table.insert(soldGoodButtons, button)
        else
            table.insert(boughtGoodNameLabels, nameLabel)
            table.insert(boughtGoodStockLabels, stockLabel)
            table.insert(boughtGoodPriceLabels, priceLabel)
            table.insert(boughtGoodTextBoxes, numberTextBox)
            table.insert(boughtGoodButtons, button)
        end

        nameLabel.caption = Material(i - 1).name
        nameLabel.color = Material(i - 1).color

        y = y + 35
    end

end

--function renderUIIndicator(px, py, size)
--
--end
--
-- this function gets called every time the window is shown on the client, ie. when a player presses F
function ResourceDepot.onShowWindow(optionIndex, material)
    local entity = Entity(Player().craftIndex)
    if not entity then return end

    local interactingFaction = Faction(entity.factionIndex)
    if not interactingFaction then return end

    if material then
        ResourceDepot.updateLine(material, interactingFaction)
    else
        for material = 1, NumMaterials() do
            ResourceDepot.updateLine(material, interactingFaction)
        end
    end
end

function ResourceDepot.updateLine(material, interactingFaction)
    remoteBuyPrice = ResourceDepot.getBuyPriceAndTax(material, interactingFaction, 1)
    remoteSellPrice = ResourceDepot.getSellPriceAndTax(material, interactingFaction, 1)

    soldGoodPriceLabels[material].caption = tostring(remoteBuyPrice)
    boughtGoodPriceLabels[material].caption = tostring(remoteSellPrice)

    -- resource shortage
    if shortageMaterial == material then
        soldGoodStockLabels[material].caption = "---"
        soldGoodTextBoxes[material]:hide()
        soldGoodButtons[material].active = false

        data = {amount = shortageAmount, material = Material(material - 1).name}
        boughtGoodStockLabels[material].caption = "---"
        boughtGoodNameLabels[material].caption = "Deliver ${amount} ${material}"%_t % data
        boughtGoodTextBoxes[material]:hide()

    else
        soldGoodStockLabels[material].caption = createMonetaryString(stock[material])
        soldGoodTextBoxes[material]:show()
        soldGoodButtons[material].active = true

        boughtGoodStockLabels[material].caption = createMonetaryString(stock[material])
        boughtGoodNameLabels[material].caption = Material(material - 1).name
        boughtGoodTextBoxes[material]:show()
    end
end
--
---- this function gets called every time the window is closed on the client
--function onCloseWindow()
--
--end
--
--function update(timeStep)
--
--end

--function updateClient(timeStep)
--
--end

function ResourceDepot.updateServer(timeStep)
    shortageTimer = shortageTimer + timeStep

    if shortageTimer >= 0 and shortageMaterial == nil then
        ResourceDepot.startShortage()
    elseif shortageTimer >= 30 * 60 then
        ResourceDepot.stopShortage()
    end
end

--function renderUI()
--
--end

-- client sided
function ResourceDepot.onBuyButtonPressed(button)
    local material = 0

    for i = 1, NumMaterials() do
        if soldGoodButtons[i].index == button.index then
            material = i
        end
    end

    local amount = soldGoodTextBoxes[material].text
    if amount == "" then
        amount = 0
    else
        amount = tonumber(amount)
    end

    invokeServerFunction("buy", material, amount);

end

function ResourceDepot.onSellButtonPressed(button)

    local material = 0

    for i = 1, NumMaterials() do
        if boughtGoodButtons[i].index == button.index then
            material = i
        end
    end

    local amount = boughtGoodTextBoxes[material].text
    if amount == "" then
        amount = 0
    else
        amount = tonumber(amount)
    end

    -- resource shortage
    if material == shortageMaterial then
        amount = shortageAmount
    end

    invokeServerFunction("sell", material, amount);
end

function ResourceDepot.onBuyTextEntered()

end

function ResourceDepot.onSellTextEntered()

end

function ResourceDepot.retrieveData()
    invokeServerFunction("getData")
end

function ResourceDepot.setData(material, amount, shortage)
    if shortage ~= nil then
        if shortage >= 0 then
            shortageMaterial = material
            shortageAmount = shortage
        else
            if shortageMaterial ~= nil then
                shortageMaterial = nil
                shortageAmount = nil
            end
        end
    end

    stock[material] = amount

    if guiInitialized then
        ResourceDepot.onShowWindow(0, material)
    end

end


-- server sided
function ResourceDepot.buy(material, amount)
    if not material then return end

    amount = amount or 0
    if amount <= 0 then return end

    local seller, ship, player = getInteractingFaction(callingPlayer, AlliancePrivilege.SpendResources)
    if not seller then return end

    local station = Entity()

    local numTraded = math.min(stock[material], amount)
    local price, tax = ResourceDepot.getBuyPriceAndTax(material, seller, numTraded);

    local errors = {}
    errors[EntityType.Station] = "You must be docked to the station to trade."%_T
    errors[EntityType.Ship] = "You must be closer to the ship to trade."%_T
    if not CheckPlayerDocked(player, station, errors) then
        return
    end

    local ok, msg, args = seller:canPay(price)
    if not ok then
        player:sendChatMessage(station, 1, msg, unpack(args))
        return
    end

    receiveTransactionTax(station, tax)

    seller:pay("Bought resources for %1% Credits."%_T, price)
    seller:receiveResource("", Material(material - 1), numTraded)

    stock[material] = stock[material] - numTraded

    ResourceDepot.improveRelations(numTraded, ship, seller, RelationChangeType.ResourceTrade)

    -- [EDE MOD] Apply tariff on resource purchase
    edeApplyTradeTariff(seller, player, price, Material(material - 1).name, "purchase")
    -- [END EDE MOD]

    -- update
    broadcastInvokeClientFunction("setData", material, stock[material])
end
callable(ResourceDepot, "buy")

function ResourceDepot.sell(material, amount)
    if not material then return end

    amount = amount or 0
    if amount <= 0 then return end

    local buyer, ship, player = getInteractingFaction(callingPlayer, AlliancePrivilege.SpendResources)
    if not buyer then return end

    local station = Entity()

    local errors = {}
    errors[EntityType.Station] = "You must be docked to the station to trade."%_T
    errors[EntityType.Ship] = "You must be closer to the ship to trade."%_T
    if not CheckPlayerDocked(player, station, errors) then
        return
    end

    local playerResources = {buyer:getResources()}
    local numTraded = math.min(playerResources[material], amount)
    if GameSettings().infiniteResources then numTraded = amount end

    local price, tax = ResourceDepot.getSellPriceAndTax(material, buyer, numTraded);

    -- resource shortage
    if material == shortageMaterial then
        if numTraded ~= shortageAmount then
            buyer:sendChatMessage("", 1, "You don't have enough ${material}."%_t % {material = Material(material - 1).name})
            return
        end
    end

    receiveTransactionTax(station, tax)

    buyer:receive("Sold resources for %1% Credits."%_T, price);
    buyer:payResource("", Material(material - 1), numTraded);

    ResourceDepot.improveRelations(numTraded, ship, buyer, RelationChangeType.ResourceTrade)

    -- [EDE MOD] Apply tariff on resource sale
    edeApplyTradeTariff(buyer, player, price, Material(material - 1).name, "sale")
    -- [END EDE MOD]

    -- when player solves resource shortage only put 1/3 of the received resources in stock to avoid exploit through rebuy
    if material == shortageMaterial then numTraded = math.floor(numTraded / 3) end

    -- Add resources to station's stock
    stock[material] = stock[material] + numTraded

    -- update
    broadcastInvokeClientFunction("setData", material, stock[material]);

    if material == shortageMaterial then
        ResourceDepot.stopShortage()
    end
end
callable(ResourceDepot, "sell")

-- relations improve when trading
function ResourceDepot.improveRelations(numTraded, ship, buyer, relationChangeType)
    relationsGained = relationsGained or {}
    relationChangeType = relationChangeType or RelationChangeType.ServiceUsage

    local gained = relationsGained[buyer.index] or 0
    local maxGainable = 10000
    local gainable = math.max(0, maxGainable - gained)

    local gain = numTraded / 20
    gain = math.min(gain, gainable)

    -- mining/unarmed ships get higher relation gain
    if ship:getNumUnarmedTurrets() > ship:getNumArmedTurrets() then
        gain = gain * 1.5
    end

    changeRelations(buyer, Faction(), gain, relationChangeType, nil, nil, Entity())

    -- remember that the player gained that many relation points
    gained = gained + gain
    relationsGained[buyer.index] = gained
end

function ResourceDepot.getBuyingFactor(material, orderingFaction)
    if ResourceDepot.fixedBuyRatio then return ResourceDepot.fixedBuyRatio end

    return getMaterialBuyingPriceFactor(Faction(), orderingFaction.index)
end

function ResourceDepot.getSellingFactor(material, orderingFaction)
    if ResourceDepot.fixedSellRatio then return ResourceDepot.fixedSellRatio end

    return getMaterialSellingPriceFactor(Faction(), orderingFaction.index)
end

function ResourceDepot.getSellPriceAndTax(material, buyer, num)
    local basePrice = round(sellPrice[material], 1)

    -- adjust for resource shortage
    if material == shortageMaterial then
        basePrice = round(sellPrice[material] * 2, 1)
    end

    if ResourceDepot.getPlayerTradesInternally(buyer) then
        return basePrice * num, 0
    end

    local price = round(basePrice * ResourceDepot.getSellingFactor(material, buyer), 1) * num
    local tax = round(basePrice * num - price, 1)

    return price, tax
end

function ResourceDepot.getBuyPriceAndTax(material, seller, num)
    local basePrice = round(buyPrice[material], 1)

    -- adjust for resource shortage
    if material == shortageMaterial then
        basePrice = round(buyPrice[material] * 2, 1)
    end

    if ResourceDepot.getPlayerTradesInternally(seller) then
        return basePrice * num, 0
    end

    local price = round(basePrice * ResourceDepot.getBuyingFactor(material, seller), 1) * num
    local tax = round(price - basePrice * num, 1)

    return price, tax
end

function ResourceDepot.getPlayerTradesInternally(buyerOrSeller)
    local faction = Faction()
    if faction.index == buyerOrSeller.index then return true end

    return isPlayerAndTheirAlliance(faction, buyerOrSeller)
end

function ResourceDepot.getSellPriceAndTaxTest(material, buyer, num)
    return ResourceDepot.getSellPriceAndTax(material, Faction(buyer), num)
end

function ResourceDepot.getBuyPriceAndTaxTest(material, seller, num)
    return ResourceDepot.getBuyPriceAndTax(material, Faction(seller), num)
end

function ResourceDepot.getData()

    local player = Player(callingPlayer)

    for i = 1, NumMaterials() do
        if i == shortageMaterial then
            invokeClientFunction(player, "setData", shortageMaterial, 0, shortageAmount)
        else
            invokeClientFunction(player, "setData", i, stock[i]);
        end
    end
end
callable(ResourceDepot, "getData")

function ResourceDepot.startShortage()
    -- find material
    local probabilities = Balancing_GetMaterialProbability(Sector():getCoordinates());
    local materials = {}
    for mat, value in pairs(probabilities) do
        if value > 0 then
            table.insert(materials, mat)
        end
    end

    local numMaterials = tablelength(materials)
    if numMaterials == 0 then
        return
    end

    shortageMaterial = materials[random():getInt(1, numMaterials)] + 1
    shortageAmount = random():getInt(5, 25) * 1000

    -- apply
    stock[shortageMaterial] = 0

    broadcastInvokeClientFunction("setData", shortageMaterial, 0, shortageAmount)

    local text = "We need %1% %2%, quickly! If you can deliver in the next 30 minutes we will pay you handsomely. /* Example: We need 150 Iron, quickly! ... */"%_T
    Sector():broadcastChatMessage(Entity().title, 0, text, shortageAmount, Material(shortageMaterial - 1).name)
end

function ResourceDepot.stopShortage()
    local material = shortageMaterial
    shortageMaterial = nil
    shortageAmount = nil
    shortageTimer = -random():getInt(45 * 60, 90 * 60)

    broadcastInvokeClientFunction("setData", material, stock[material], -1)
end

function ResourceDepot.setStock(value)
    stock = value
end
