-- EDE Diplomatic States
-- Pure data/logic module — no Avorion API calls (testable outside the game)

package.path = package.path .. ";data/scripts/lib/?.lua"

local States = {}

-- Custom diplomatic states layered on top of Avorion's built-in relation system.
-- These are stored via setValue/getValue and tracked in our own data layer.
States.Type = {
    NONE = "none",                       -- No special diplomatic state
    TRADE_AGREEMENT = "trade_agreement", -- Reduced tariffs, preferred trade partner
    NON_AGGRESSION = "non_aggression",   -- Factions agree not to attack each other
    TARIFF = "tariff",                   -- Import/export tax on trade
    EMBARGO = "embargo",                 -- Full trade block between factions
    SANCTIONS = "sanctions",             -- Multi-faction coordinated embargo
    BLOCKADE = "blockade",               -- Physical trade route denial
}

-- Default parameters for each state type
States.Defaults = {
    [States.Type.TARIFF] = {
        rate = 0.15, -- 15% default tariff rate
    },
    [States.Type.TRADE_AGREEMENT] = {
        discount = 0.10, -- 10% price discount
    },
}

return States
