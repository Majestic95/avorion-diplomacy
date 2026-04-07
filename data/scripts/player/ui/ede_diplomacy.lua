-- EDE Diplomacy Panel — tab inside the Player Window (press I).
-- Sits next to the vanilla Diplomacy tab.
--
-- Attach to player: /run Player():addScriptOnce("player/ui/ede_diplomacy.lua")

package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace EdeDiplomacy
EdeDiplomacy = {}

-- Client UI elements
local tab = nil
local factionLines = {}
local overviewStatusLabel = nil
local targetCombo = nil
local tariffRateSlider = nil
local tariffRateLabel = nil
local agreementDiscountSlider = nil
local agreementDiscountLabel = nil
local actionStatusLabel = nil
local tariffPreviewLabel = nil
local agreementPreviewLabel = nil

-- Cached data
local cachedFactions = {}

-- ============================================================
-- INITIALIZATION
-- ============================================================

function EdeDiplomacy.initialize()
    if onClient() then
        tab = PlayerWindow():createTab("EDE Diplomacy", "data/textures/icons/domino-mask.png", "Economics & Diplomacy")
        PlayerWindow():moveTabToPosition(tab, 4)
        tab.onShowFunction = "onShowTab"
        EdeDiplomacy.buildUI(tab)
    end
end

function EdeDiplomacy.onShowTab()
    invokeServerFunction("serverGetDiplomacyData")
end

-- Server-side periodic update: every 3 real hours (10800 seconds = 1 game-day)
-- Refreshes power scores and deducts tariff enforcement costs
local CYCLE_INTERVAL = 10800 -- 3 real hours in seconds
local cycleTimer = 0

function EdeDiplomacy.getUpdateInterval()
    return 60 -- check every 60 seconds
end

function EdeDiplomacy.updateServer(timestep)
    cycleTimer = cycleTimer + timestep

    if cycleTimer >= CYCLE_INTERVAL then
        cycleTimer = 0
        EdeDiplomacy.processCycle()
    end
end

function EdeDiplomacy.processCycle()
    local player = Player()
    if not player then return end

    local TariffManager = include("diplomacy/tariff_manager")
    local PowerScore = include("economy/power_score")
    local store = Server()
    local playerIndex = player.index

    -- Refresh territory scan
    local sx, sy = Sector():getCoordinates()
    scanTerritory(sx, sy)

    local playerScore = calcFactionScore(player)

    -- Process all active tariffs imposed by this player
    local activeTariffs = TariffManager.getAllActive(store)
    for _, pair in ipairs(activeTariffs) do
        if pair.imposer == playerIndex then
            local targetFaction = Faction(pair.target)
            if targetFaction then
                local targetScore = calcFactionScore(targetFaction)
                local tariff = TariffManager.get(store, pair.imposer, pair.target)
                local rate = tariff and tariff.rate or 0.15
                local cost = PowerScore.tariffCost(playerScore, targetScore, rate)

                local active, charged = TariffManager.processPaymentCycle(
                    store, pair.imposer, pair.target,
                    player.money, playerScore, targetScore,
                    Server().unpausedRuntime
                )

                if charged > 0 then
                    player:sendChatMessage("EDE", ChatMessageType.Normal,
                        string.format("Tariff enforcement cost: -%dk cr (on %s)",
                            math.floor(charged / 1000), targetFaction.name))
                end

                if not active then
                    player:sendChatMessage("EDE", ChatMessageType.Warning,
                        string.format("Tariff on %s has lapsed — insufficient funds!", targetFaction.name))
                end
            end
        end
    end
end

-- ============================================================
-- CLIENT: Build UI
-- ============================================================

function EdeDiplomacy.buildUI(tab)
    local size = tab.rect.size
    local vsplit = UIVerticalSplitter(Rect(size), 10, 0, 0.55)

    -- ==================
    -- LEFT: Overview
    -- ==================
    local leftLister = UIVerticalLister(vsplit.left, 4, 5)

    local headerRect = leftLister:placeCenter(vec2(leftLister.inner.width, 22))
    local hsplit = UIArbitraryVerticalSplitter(headerRect, 5, 0, 160, 245, 330)
    tab:createLabel(hsplit:partition(0).lower, "Faction", 13)
    tab:createLabel(hsplit:partition(1).lower, "Score", 13)
    tab:createLabel(hsplit:partition(2).lower, "Tariff", 13)
    tab:createLabel(hsplit:partition(3).lower, "Agree.", 13)

    factionLines = {}
    for i = 1, 14 do
        local rowRect = leftLister:placeCenter(vec2(leftLister.inner.width, 18))
        local rsplit = UIArbitraryVerticalSplitter(rowRect, 5, 0, 160, 245, 330)
        local line = {}
        line.nameLabel = tab:createLabel(rsplit:partition(0).lower, "", 12)
        line.nameLabel.shortenText = true
        line.nameLabel.width = 155
        line.scoreLabel = tab:createLabel(rsplit:partition(1).lower, "", 12)
        line.tariffLabel = tab:createLabel(rsplit:partition(2).lower, "", 12)
        line.agreementLabel = tab:createLabel(rsplit:partition(3).lower, "", 12)
        factionLines[i] = line
    end

    local statusRect = leftLister:placeCenter(vec2(leftLister.inner.width, 18))
    overviewStatusLabel = tab:createLabel(statusRect.lower, "", 11)

    -- ==================
    -- RIGHT: Actions
    -- ==================
    local rightLister = UIVerticalLister(vsplit.right, 5, 5)

    -- Target selector
    local targetHeaderRect = rightLister:placeCenter(vec2(rightLister.inner.width, 20))
    tab:createLabel(targetHeaderRect.lower, "Target Faction:", 13)
    local targetComboRect = rightLister:placeCenter(vec2(rightLister.inner.width, 25))
    targetCombo = tab:createValueComboBox(targetComboRect, "onTargetFactionChanged")

    rightLister:placeCenter(vec2(rightLister.inner.width, 4))

    -- Tariff section
    local tariffHeader = rightLister:placeCenter(vec2(rightLister.inner.width, 18))
    tab:createLabel(tariffHeader.lower, "TARIFFS", 13)

    local tariffSliderRect = rightLister:placeCenter(vec2(rightLister.inner.width, 25))
    local tSplit = UIVerticalSplitter(tariffSliderRect, 5, 0, 0.75)
    tariffRateSlider = tab:createSlider(tSplit.left, 1, 50, 49, "", "onTariffSliderChanged")
    tariffRateSlider.value = 15
    tariffRateLabel = tab:createLabel(tSplit.right.lower, "15%", 13)

    -- Tariff enforcement preview
    local tariffPreviewRect = rightLister:placeCenter(vec2(rightLister.inner.width, 18))
    tariffPreviewLabel = tab:createLabel(tariffPreviewRect.lower, "", 11)

    local tariffBtnRect = rightLister:placeCenter(vec2(rightLister.inner.width, 28))
    local tBtnSplit = UIVerticalSplitter(tariffBtnRect, 5, 0, 0.5)
    local declareBtn = tab:createButton(tBtnSplit.left, "Declare", "onDeclareTariffPressed")
    declareBtn.uppercase = false
    local removeBtn = tab:createButton(tBtnSplit.right, "Remove", "onRemoveTariffPressed")
    removeBtn.uppercase = false

    rightLister:placeCenter(vec2(rightLister.inner.width, 4))

    -- Agreement section
    local agreeHeader = rightLister:placeCenter(vec2(rightLister.inner.width, 18))
    tab:createLabel(agreeHeader.lower, "TRADE AGREEMENTS", 13)

    local agreeSliderRect = rightLister:placeCenter(vec2(rightLister.inner.width, 25))
    local aSplit = UIVerticalSplitter(agreeSliderRect, 5, 0, 0.75)
    agreementDiscountSlider = tab:createSlider(aSplit.left, 1, 30, 29, "", "onAgreementSliderChanged")
    agreementDiscountSlider.value = 10
    agreementDiscountLabel = tab:createLabel(aSplit.right.lower, "10%", 13)

    -- Agreement acceptance preview
    local agreePreviewRect = rightLister:placeCenter(vec2(rightLister.inner.width, 18))
    agreementPreviewLabel = tab:createLabel(agreePreviewRect.lower, "", 11)

    local agreeBtnRect = rightLister:placeCenter(vec2(rightLister.inner.width, 28))
    local aBtnSplit = UIVerticalSplitter(agreeBtnRect, 5, 0, 0.5)
    local proposeBtn = tab:createButton(aBtnSplit.left, "Propose", "onProposeAgreementPressed")
    proposeBtn.uppercase = false
    local cancelBtn = tab:createButton(aBtnSplit.right, "Cancel", "onCancelAgreementPressed")
    cancelBtn.uppercase = false

    rightLister:placeCenter(vec2(rightLister.inner.width, 4))

    local actionRect = rightLister:placeCenter(vec2(rightLister.inner.width, 18))
    actionStatusLabel = tab:createLabel(actionRect.lower, "", 11)

    -- Confirmation dialog (hidden by default)
    EdeDiplomacy.buildConfirmDialog(tab)
end

-- Confirmation dialog state
local confirmWindow = nil
local confirmTextField = nil
local confirmCallback = nil
local confirmTargetIndex = nil
local confirmRate = nil

function EdeDiplomacy.buildConfirmDialog(container)
    confirmWindow = container:createWindow(Rect(vec2(450, 160)))
    confirmWindow.transparency = 0.1
    confirmWindow.consumeAllEvents = true
    confirmWindow.showCloseButton = true
    confirmWindow.closeableWithEscape = true
    confirmWindow.moveable = true
    confirmWindow.caption = "Confirm Action"
    confirmWindow:hide()

    local lister = UIVerticalLister(Rect(confirmWindow.size), 10, 10)
    local topSplit = UIVerticalSplitter(lister:nextRect(80), 10, 0, 0.5)
    topSplit:setLeftQuadratic()

    local warningIcon = confirmWindow:createPicture(topSplit.left, "data/textures/icons/hazard-sign.png")
    warningIcon.isIcon = true
    warningIcon.color = ColorRGB(1, 1, 0)

    confirmTextField = confirmWindow:createTextField(topSplit.right, "")
    confirmTextField.fontSize = 13

    local btnSplit = UIVerticalSplitter(lister:nextRect(30), 10, 0, 0.5)
    local confirmBtn = confirmWindow:createButton(btnSplit.left, "Confirm", "onConfirmDialogYes")
    local cancelBtn = confirmWindow:createButton(btnSplit.right, "Cancel", "onConfirmDialogNo")
end

function EdeDiplomacy.showConfirmDialog(title, description, callback, targetIndex, rate)
    if not confirmWindow then return end
    confirmWindow.caption = title
    confirmTextField.text = description
    confirmCallback = callback
    confirmTargetIndex = targetIndex
    confirmRate = rate
    confirmWindow:show()
end

function EdeDiplomacy.onConfirmDialogYes()
    if confirmWindow then confirmWindow:hide() end
    if confirmCallback then
        confirmCallback(confirmTargetIndex, confirmRate)
    end
end

function EdeDiplomacy.onConfirmDialogNo()
    if confirmWindow then confirmWindow:hide() end
    confirmCallback = nil
end

-- ============================================================
-- CLIENT: Callbacks
-- ============================================================

function EdeDiplomacy.onTariffSliderChanged(slider)
    if tariffRateLabel and slider then
        tariffRateLabel.caption = tostring(math.floor(slider.value)) .. "%"
    end
end

function EdeDiplomacy.onAgreementSliderChanged(slider)
    if agreementDiscountLabel and slider then
        agreementDiscountLabel.caption = tostring(math.floor(slider.value)) .. "%"
    end
end

function EdeDiplomacy.onTargetFactionChanged()
    -- Request preview from server when target changes
    local targetIndex = EdeDiplomacy.getSelectedFactionIndex()
    if targetIndex then
        invokeServerFunction("serverGetPreview", targetIndex)
    else
        EdeDiplomacy.clearPreviews()
    end
end

function EdeDiplomacy.onDeclareTariffPressed()
    local targetIndex = EdeDiplomacy.getSelectedFactionIndex()
    if not targetIndex then
        EdeDiplomacy.setActionStatus("Select a target faction first.")
        return
    end
    local rate = math.floor(tariffRateSlider.value) / 100
    local penalty = math.floor(rate * 100000)

    -- Find faction name from cached data
    local factionName = "Unknown"
    for _, f in ipairs(cachedFactions) do
        if f.index == targetIndex then factionName = f.name; break end
    end

    local desc = string.format(
        "Declaring a %d%% tariff on %s will:\n\n" ..
        "- Reset relations to neutral (0) if currently positive\n" ..
        "- Apply a -%d relations penalty\n" ..
        "- Relations cannot be positive while tariff is active\n" ..
        "- May provoke retaliation or war\n\n" ..
        "Proceed?",
        math.floor(rate * 100), factionName, penalty)

    EdeDiplomacy.showConfirmDialog(
        "Declare Tariff",
        desc,
        function(ti, r)
            invokeServerFunction("serverDeclareTariff", ti, r)
        end,
        targetIndex,
        rate
    )
end

function EdeDiplomacy.onRemoveTariffPressed()
    local targetIndex = EdeDiplomacy.getSelectedFactionIndex()
    if not targetIndex then
        EdeDiplomacy.setActionStatus("Select a target faction first.")
        return
    end
    invokeServerFunction("serverRemoveTariff", targetIndex)
end

function EdeDiplomacy.onProposeAgreementPressed()
    local targetIndex = EdeDiplomacy.getSelectedFactionIndex()
    if not targetIndex then
        EdeDiplomacy.setActionStatus("Select a target faction first.")
        return
    end
    local discount = math.floor(agreementDiscountSlider.value) / 100
    invokeServerFunction("serverProposeAgreement", targetIndex, discount)
end

function EdeDiplomacy.onCancelAgreementPressed()
    local targetIndex = EdeDiplomacy.getSelectedFactionIndex()
    if not targetIndex then
        EdeDiplomacy.setActionStatus("Select a target faction first.")
        return
    end
    invokeServerFunction("serverCancelAgreement", targetIndex)
end

function EdeDiplomacy.getSelectedFactionIndex()
    if not targetCombo then return nil end
    local selected = targetCombo.selectedValue
    if selected and selected ~= 0 then return selected end
    return nil
end

function EdeDiplomacy.setActionStatus(text)
    if actionStatusLabel then actionStatusLabel.caption = text or "" end
end

function EdeDiplomacy.clearPreviews()
    if tariffPreviewLabel then
        tariffPreviewLabel.caption = ""
    end
    if agreementPreviewLabel then
        agreementPreviewLabel.caption = ""
    end
end

-- ============================================================
-- CLIENT: Receive data from server
-- ============================================================

function EdeDiplomacy.clientReceiveDiplomacyData(data)
    if not data then return end
    cachedFactions = data.factions or {}

    for i, line in ipairs(factionLines) do
        local f = cachedFactions[i]
        if f then
            line.nameLabel.caption = f.name or "Unknown"
            line.scoreLabel.caption = tostring(f.score or 0)
            if f.tariff_rate then
                line.tariffLabel.caption = tostring(math.floor(f.tariff_rate * 100)) .. "%"
                line.tariffLabel.color = ColorRGB(1.0, 0.4, 0.4)
            else
                line.tariffLabel.caption = "-"
                line.tariffLabel.color = ColorRGB(0.6, 0.6, 0.6)
            end
            if f.has_agreement then
                line.agreementLabel.caption = "Yes"
                line.agreementLabel.color = ColorRGB(0.4, 1.0, 0.4)
            else
                line.agreementLabel.caption = "-"
                line.agreementLabel.color = ColorRGB(0.6, 0.6, 0.6)
            end
        else
            line.nameLabel.caption = ""
            line.scoreLabel.caption = ""
            line.tariffLabel.caption = ""
            line.agreementLabel.caption = ""
        end
    end

    if overviewStatusLabel then
        overviewStatusLabel.caption = string.format(
            "Your Score: %d  |  %d factions", data.playerScore or 0, #cachedFactions)
    end

    if targetCombo then
        targetCombo:clear()
        targetCombo:addEntry(0, "-- Select Faction --")
        for _, f in ipairs(cachedFactions) do
            if f.index then
                targetCombo:addEntry(f.index, f.name or ("Faction " .. tostring(f.index)))
            end
        end
    end

    EdeDiplomacy.clearPreviews()
end

function EdeDiplomacy.clientReceiveActionResult(success, message)
    EdeDiplomacy.setActionStatus(message or "")
    if success then
        invokeServerFunction("serverGetDiplomacyData")
    end
end

function EdeDiplomacy.clientReceivePreview(tariffPreview, agreementPreview)
    if tariffPreviewLabel then
        tariffPreviewLabel.caption = tariffPreview or ""
        if tariffPreview and tariffPreview:find("Can enforce") then
            tariffPreviewLabel.color = ColorRGB(0.4, 1.0, 0.4)
        else
            tariffPreviewLabel.color = ColorRGB(1.0, 0.4, 0.4)
        end
    end
    if agreementPreviewLabel then
        agreementPreviewLabel.caption = agreementPreview or ""
        if agreementPreview and agreementPreview:find("Will accept") then
            agreementPreviewLabel.color = ColorRGB(0.4, 1.0, 0.4)
        else
            agreementPreviewLabel.color = ColorRGB(1.0, 0.6, 0.2)
        end
    end
end

-- ============================================================
-- SERVER: Helpers
-- ============================================================

-- Territory cache: faction_index → sector count (refreshed per tab open)
local territoryCounts = {}

-- Scan territory around the player's current position using Galaxy():getControllingFaction()
-- Samples a grid centered on the player. Step size keeps it fast.
local function scanTerritory(centerX, centerY)
    territoryCounts = {}
    local galaxy = Galaxy()
    local step = 15
    local radius = 150

    centerX = centerX or 0
    centerY = centerY or 0

    for x = centerX - radius, centerX + radius, step do
        for y = centerY - radius, centerY + radius, step do
            local controllingFaction = galaxy:getControllingFaction(x, y)
            if controllingFaction then
                local fi = controllingFaction.index
                if fi then
                    territoryCounts[fi] = (territoryCounts[fi] or 0) + 1
                end
            end
        end
    end
end

-- Map stateForm to our archetype names for power score bonus
-- stateForm values from vanilla faction.lua (FactionStateFormType enum, 1-indexed)
local stateFormToArchetype = {
    -- 1=Vanilla, 2=Emirate, 3=States, 4=Planets, 5=Kingdom, 6=Army
    -- 7=Empire, 8=Clan, 9=Church, 10=Corporation, 11=Federation, 12=Collective
    -- 13=Followers, 14=Organization, 15=Alliance, 16=Republic, 17=Commonwealth
    -- 18=Dominion, 19=Syndicate, 20=Guild, 21=Buccaneers, 22=Conglomerate
    [2] = "Traditional", [5] = "Traditional", [7] = "Traditional",
    [3] = "Independent", [4] = "Independent", [16] = "Independent", [18] = "Independent",
    [6] = "Militaristic", [8] = "Militaristic", [21] = "Militaristic",
    [9] = "Religious", [13] = "Religious",
    [10] = "Corporate", [19] = "Corporate", [20] = "Corporate", [22] = "Corporate",
    [11] = "Alliance", [15] = "Alliance", [17] = "Alliance",
    [12] = "Sect",
}

-- Calculate power score for any faction type
local function calcFactionScore(faction)
    local PowerScore = include("economy/power_score")

    -- numShips/numStations only exist on Player and Alliance, not base Faction (AI)
    local ships = 0
    local stations = 0
    local ok_ships = pcall(function() ships = faction.numShips or 0 end)
    local ok_stations = pcall(function() stations = faction.numStations or 0 end)
    if not ok_ships then ships = 0 end
    if not ok_stations then stations = 0 end

    local sectors = territoryCounts[faction.index] or 0

    -- Map AI faction's stateForm to archetype for bonus
    local archetype = nil
    if faction.isAIFaction then
        local sf = faction.stateForm
        if sf then
            archetype = stateFormToArchetype[sf]
        end
        archetype = archetype or "Vanilla"
    end

    return PowerScore.calculate({
        ships = ships,
        stations = stations,
        money = faction.money or 0,
        sectors = sectors,
        archetype = archetype,
    })
end

-- ============================================================
-- SERVER: Data gathering
-- ============================================================

function EdeDiplomacy.serverGetDiplomacyData()
    if not onServer() then return end
    local player = Player(callingPlayer)
    if not player then return end

    local TariffManager = include("diplomacy/tariff_manager")
    local AgreementManager = include("diplomacy/agreement_manager")
    local store = Server()
    local playerIndex = player.index

    -- Scan territory for all factions centered on player's location
    local sx, sy = Sector():getCoordinates()
    scanTerritory(sx, sy)

    local playerScore = calcFactionScore(player)

    -- Use getAllRelations() to match vanilla diplomacy — only show factions the player has met
    local factions = {}

    for _, relation in pairs({player:getAllRelations()}) do
        local fi = relation.factionIndex
        if fi and fi ~= playerIndex then
            local faction = Faction(fi)
            if faction then
                local fScore = calcFactionScore(faction)

                local tariff = TariffManager.get(store, playerIndex, fi)
                local tariff_on_us = TariffManager.get(store, fi, playerIndex)
                local agreement = AgreementManager.getActive(store, playerIndex, fi)

                local tariff_rate = nil
                if tariff and tariff.active then
                    tariff_rate = tariff.rate
                elseif tariff_on_us and tariff_on_us.active then
                    tariff_rate = tariff_on_us.rate
                end

                -- Enforce: relations cannot be positive while any tariff is active
                if tariff_rate then
                    local currentRelations = player:getRelations(fi)
                    if currentRelations > 0 then
                        Galaxy():setFactionRelations(player, faction, 0)
                    end
                end

                -- Clean faction name: strip dev comments like /*...*/
                local displayName = faction.name or "Unknown"
                displayName = displayName:gsub("/%*.*%*/", ""):match("^%s*(.-)%s*$")
                if displayName == "" then displayName = "Unknown Faction" end

                table.insert(factions, {
                    index = fi,
                    name = displayName,
                    score = fScore,
                    tariff_rate = tariff_rate,
                    has_agreement = agreement ~= nil,
                })
            end
        end
    end

    table.sort(factions, function(a, b) return a.score > b.score end)

    local display = {}
    for i = 1, math.min(#factions, 14) do
        display[i] = factions[i]
    end

    invokeClientFunction(player, "clientReceiveDiplomacyData", {
        factions = display,
        playerIndex = playerIndex,
        playerScore = playerScore,
    })
end

-- ============================================================
-- SERVER: Preview (enforcement check + AI acceptance check)
-- ============================================================

function EdeDiplomacy.serverGetPreview(targetIndex)
    if not onServer() then return end
    local player = Player(callingPlayer)
    if not player then return end

    local PowerScore = include("economy/power_score")
    local targetFaction = Faction(targetIndex)
    if not targetFaction then return end

    local playerScore = calcFactionScore(player)
    local targetScore = calcFactionScore(targetFaction)

    -- Tariff preview: show cost range at 15% and 50%
    local canEnforce, ratio = PowerScore.canEnforce(playerScore, targetScore, "tariff")
    local tariffPreview
    if canEnforce then
        local cost15 = PowerScore.tariffCost(playerScore, targetScore, 0.15)
        local cost50 = PowerScore.tariffCost(playerScore, targetScore, 0.50)
        tariffPreview = string.format("Can enforce | Cost: %dk (15%%) to %dk (50%%) /cycle",
            math.floor(cost15 / 1000), math.floor(cost50 / 1000))
    else
        tariffPreview = string.format("Cannot enforce (%.0f%% power, need 30%%)", ratio * 100)
    end

    -- Agreement preview
    local agreementPreview
    if targetFaction.isAIFaction then
        local relations = targetFaction:getRelations(player.index)
        if relations >= 30000 then
            agreementPreview = string.format("Will accept (relations: %d)", relations)
        elseif relations >= 10000 then
            agreementPreview = string.format("Will likely accept (relations: %d)", relations)
        elseif relations >= 0 then
            agreementPreview = string.format("May reject (relations: %d, needs improvement)", relations)
        else
            agreementPreview = string.format("Will reject (relations: %d, too hostile)", relations)
        end
    elseif targetFaction.isPlayer or targetFaction.isAlliance then
        agreementPreview = "Player/Alliance — proposal will be sent"
    else
        agreementPreview = "Unknown faction type"
    end

    invokeClientFunction(player, "clientReceivePreview", tariffPreview, agreementPreview)
end

-- ============================================================
-- SERVER: Actions
-- ============================================================

function EdeDiplomacy.serverDeclareTariff(targetIndex, rate)
    if not onServer() then return end
    local player = Player(callingPlayer)
    if not player then return end

    local TariffManager = include("diplomacy/tariff_manager")
    local store = Server()

    local targetFaction = Faction(targetIndex)
    if not targetFaction then
        invokeClientFunction(player, "clientReceiveActionResult", false, "Faction not found.")
        return
    end

    local pScore = calcFactionScore(player)
    local tScore = calcFactionScore(targetFaction)

    local ok, err = TariffManager.declare(
        store, player.index, targetIndex,
        pScore, tScore, rate, Server().unpausedRuntime
    )

    if ok then
        -- Apply relation penalty
        -- Step 1: clamp to 0 if positive
        local currentRelations = player:getRelations(targetIndex)
        if currentRelations > 0 then
            Galaxy():setFactionRelations(player, targetFaction, 0)
        end
        -- Step 2: subtract penalty based on tariff rate (rate × 100,000)
        local penalty = math.floor(rate * 100000)
        Galaxy():changeFactionRelations(player, targetFaction, -penalty)

        local newRelations = player:getRelations(targetIndex)
        local msg = string.format("Tariff declared: %d%% on %s (relations: %d)",
            math.floor(rate * 100), targetFaction.name, newRelations)
        player:sendChatMessage("EDE", ChatMessageType.Normal, msg)
        invokeClientFunction(player, "clientReceiveActionResult", true, msg)
    else
        invokeClientFunction(player, "clientReceiveActionResult", false, err or "Failed.")
    end
end

function EdeDiplomacy.serverRemoveTariff(targetIndex)
    if not onServer() then return end
    local player = Player(callingPlayer)
    if not player then return end

    local TariffManager = include("diplomacy/tariff_manager")
    local store = Server()

    local ok = TariffManager.remove(store, player.index, targetIndex)
    if ok then
        local name = Faction(targetIndex) and Faction(targetIndex).name or tostring(targetIndex)
        local msg = "Tariff on " .. name .. " removed."
        player:sendChatMessage("EDE", ChatMessageType.Normal, msg)
        invokeClientFunction(player, "clientReceiveActionResult", true, msg)
    else
        invokeClientFunction(player, "clientReceiveActionResult", false, "No active tariff to remove.")
    end
end

function EdeDiplomacy.serverProposeAgreement(targetIndex, discount)
    if not onServer() then return end
    local player = Player(callingPlayer)
    if not player then return end

    local AgreementManager = include("diplomacy/agreement_manager")
    local store = Server()

    local targetFaction = Faction(targetIndex)
    if not targetFaction then
        invokeClientFunction(player, "clientReceiveActionResult", false, "Faction not found.")
        return
    end

    local ok, err = AgreementManager.propose(
        store, player.index, targetIndex,
        discount, discount, Server().unpausedRuntime
    )

    if not ok then
        invokeClientFunction(player, "clientReceiveActionResult", false, err or "Failed.")
        return
    end

    -- AI faction: evaluate acceptance based on relations
    if targetFaction.isAIFaction then
        local relations = targetFaction:getRelations(player.index)

        -- Acceptance thresholds based on relations
        -- Positive relations = more likely to accept
        if relations >= 10000 then
            AgreementManager.accept(store, player.index, targetIndex, Server().unpausedRuntime)
            local msg = string.format("Trade agreement with %s accepted (mutual %d%%)",
                targetFaction.name, math.floor(discount * 100))
            player:sendChatMessage("EDE", ChatMessageType.Normal, msg)
            invokeClientFunction(player, "clientReceiveActionResult", true, msg)
        else
            -- Reject — remove the proposal
            AgreementManager.decline(store, player.index, targetIndex)
            local msg = string.format("%s rejected your trade proposal (relations too low: %d)",
                targetFaction.name, relations)
            player:sendChatMessage("EDE", ChatMessageType.Normal, msg)
            invokeClientFunction(player, "clientReceiveActionResult", false, msg)
        end
    else
        -- Player/Alliance: proposal is pending (they decide later)
        local msg = string.format("Agreement proposed to %s (%d%%)",
            targetFaction.name, math.floor(discount * 100))
        invokeClientFunction(player, "clientReceiveActionResult", true, msg)
    end
end

function EdeDiplomacy.serverCancelAgreement(targetIndex)
    if not onServer() then return end
    local player = Player(callingPlayer)
    if not player then return end

    local AgreementManager = include("diplomacy/agreement_manager")
    local store = Server()

    local ok = AgreementManager.cancel(store, player.index, targetIndex)
    if ok then
        local name = Faction(targetIndex) and Faction(targetIndex).name or tostring(targetIndex)
        local msg = "Agreement with " .. name .. " cancelled."
        player:sendChatMessage("EDE", ChatMessageType.Normal, msg)
        invokeClientFunction(player, "clientReceiveActionResult", true, msg)
    else
        invokeClientFunction(player, "clientReceiveActionResult", false, "No active agreement to cancel.")
    end
end

-- ============================================================
-- RPC declarations
-- ============================================================
callable(EdeDiplomacy, "serverGetDiplomacyData")
callable(EdeDiplomacy, "serverGetPreview")
callable(EdeDiplomacy, "serverDeclareTariff")
callable(EdeDiplomacy, "serverRemoveTariff")
callable(EdeDiplomacy, "serverProposeAgreement")
callable(EdeDiplomacy, "serverCancelAgreement")
callable(EdeDiplomacy, "clientReceiveDiplomacyData")
callable(EdeDiplomacy, "clientReceiveActionResult")
callable(EdeDiplomacy, "clientReceivePreview")
