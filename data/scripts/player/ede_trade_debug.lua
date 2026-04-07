-- EDE Trade Debug — minimal script to test if trade callbacks reach player scripts.
-- Attach: /run Player():addScriptOnce("player/ede_trade_debug.lua")
-- Remove: /run Player():removeScript("player/ede_trade_debug.lua")

package.path = package.path .. ";data/scripts/lib/?.lua"

function initialize()
    if onServer() then
        print("[EDE DEBUG] Trade debug script initialized on server")

        -- Try both approaches: with and without registerCallback
        local player = Player()
        player:registerCallback("onTradingManagerBuyFromPlayer", "onBuyCallback")
        player:registerCallback("onTradingManagerSellToPlayer", "onSellCallback")
        print("[EDE DEBUG] Callbacks registered")
    end
end

-- Approach 1: named exactly like the callback (auto-dispatch)
function onTradingManagerBuyFromPlayer(goodName, amount, price)
    print("[EDE DEBUG] onTradingManagerBuyFromPlayer fired! good=" .. tostring(goodName) .. " amount=" .. tostring(amount) .. " price=" .. tostring(price))
    local player = Player()
    if player then
        player:sendChatMessage("EDE DEBUG", ChatMessageType.Normal,
            "BuyFromPlayer callback fired: " .. tostring(goodName) .. " x" .. tostring(amount))
    end
end

function onTradingManagerSellToPlayer(goodName, amount, price)
    print("[EDE DEBUG] onTradingManagerSellToPlayer fired! good=" .. tostring(goodName) .. " amount=" .. tostring(amount) .. " price=" .. tostring(price))
    local player = Player()
    if player then
        player:sendChatMessage("EDE DEBUG", ChatMessageType.Normal,
            "SellToPlayer callback fired: " .. tostring(goodName) .. " x" .. tostring(amount))
    end
end

-- Approach 2: registered with different function names
function onBuyCallback(goodName, amount, price)
    print("[EDE DEBUG] onBuyCallback (registered) fired!")
    local player = Player()
    if player then
        player:sendChatMessage("EDE DEBUG", ChatMessageType.Normal,
            "REGISTERED BuyCallback fired: " .. tostring(goodName))
    end
end

function onSellCallback(goodName, amount, price)
    print("[EDE DEBUG] onSellCallback (registered) fired!")
    local player = Player()
    if player then
        player:sendChatMessage("EDE DEBUG", ChatMessageType.Normal,
            "REGISTERED SellCallback fired: " .. tostring(goodName))
    end
end
