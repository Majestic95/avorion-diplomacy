-- EDE Power Projection Score Calculator
-- Pure math module — no Avorion API calls (testable outside the game)
--
-- The power score gates diplomatic enforcement actions and determines
-- ongoing enforcement costs. It aggregates ships, stations, money,
-- and controlled sectors into a single comparable number.

local PowerScore = {}

-- Default weights (tunable constants)
PowerScore.Weights = {
    SHIP = 10,            -- points per ship owned
    STATION = 25,         -- points per station owned
    MONEY = 1,            -- points per 100K credits
    SECTOR = 15,          -- points per controlled sector
    MONEY_DIVISOR = 100000, -- credits per 1 point of money score
}

-- Archetype bonuses for AI factions (flat bonus added to score)
-- Keys match FactionArchetype values from vanilla faction.lua
PowerScore.ArchetypeBonus = {
    Vanilla = 0,
    Traditional = 50,
    Independent = 25,
    Militaristic = 100,
    Religious = 50,
    Corporate = 75,
    Alliance = 50,
    Sect = 25,
}

-- Enforcement thresholds (minimum your_score / target_score ratio)
PowerScore.Thresholds = {
    TARIFF = 0.30,   -- 30% of target's score to declare tariff
    EMBARGO = 0.50,  -- 50% of target's score to declare embargo
}

--- Calculate the power projection score for a faction.
--- @param data table { ships=number, stations=number, money=number, sectors=number, archetype=string|nil }
--- @param weights table|nil Optional custom weights (defaults to PowerScore.Weights)
--- @return number score The calculated power score (floored to integer, minimum 0)
function PowerScore.calculate(data, weights)
    local w = weights or PowerScore.Weights

    local ships = math.max(data.ships or 0, 0)
    local stations = math.max(data.stations or 0, 0)
    local money = math.max(data.money or 0, 0)
    local sectors = math.max(data.sectors or 0, 0)
    local archetype = data.archetype

    local score = 0
    score = score + ships * (w.SHIP or PowerScore.Weights.SHIP)
    score = score + stations * (w.STATION or PowerScore.Weights.STATION)
    local money_divisor = w.MONEY_DIVISOR or PowerScore.Weights.MONEY_DIVISOR
    score = score + math.floor(money / money_divisor) * (w.MONEY or PowerScore.Weights.MONEY)
    score = score + sectors * (w.SECTOR or PowerScore.Weights.SECTOR)

    if archetype and PowerScore.ArchetypeBonus[archetype] then
        score = score + PowerScore.ArchetypeBonus[archetype]
    end

    return math.max(math.floor(score), 0)
end

--- Check if an actor can enforce a diplomatic action against a target.
--- @param actor_score number The enforcing faction's power score
--- @param target_score number The target faction's power score
--- @param action_type string "tariff" or "embargo"
--- @return boolean can_enforce Whether the actor meets the enforcement threshold
--- @return number ratio The actual score ratio (actor/target)
function PowerScore.canEnforce(actor_score, target_score, action_type)
    if target_score <= 0 then
        return true, 1.0
    end
    if actor_score <= 0 then
        return false, 0.0
    end

    local ratio = actor_score / target_score
    local threshold = PowerScore.Thresholds[string.upper(action_type)]
    if not threshold then
        return false, ratio
    end

    return ratio >= threshold, ratio
end

--- Calculate the per-cycle enforcement cost for maintaining a diplomatic action.
--- Cost scales with the power delta — stronger targets are more expensive to enforce against.
--- @param actor_score number The enforcing faction's power score
--- @param target_score number The target faction's power score
--- @param base_cost number The base cost per cycle for this action type
--- @return number cost The credits owed per game-day cycle (floored to integer)
function PowerScore.enforcementCost(actor_score, target_score, base_cost)
    if actor_score <= 0 then
        return base_cost * 10
    end
    if target_score <= 0 then
        return math.floor(base_cost * 0.5)
    end

    local ratio = target_score / actor_score
    -- Floor at 0.5x base cost (enforcing against much weaker faction)
    -- No ceiling — enforcing against a much stronger faction gets very expensive
    local multiplier = math.max(ratio, 0.5)
    return math.floor(base_cost * multiplier + 0.5)
end

--- Compare two factions and return a summary.
--- @param actor_data table Actor faction data (same format as calculate input)
--- @param target_data table Target faction data
--- @return table comparison { actor_score, target_score, ratio, can_tariff, can_embargo, tariff_cost, embargo_cost }
function PowerScore.compare(actor_data, target_data, config)
    config = config or {}
    local actor_score = PowerScore.calculate(actor_data)
    local target_score = PowerScore.calculate(target_data)

    local can_tariff, ratio = PowerScore.canEnforce(actor_score, target_score, "tariff")
    local can_embargo, _ = PowerScore.canEnforce(actor_score, target_score, "embargo")

    local tariff_base = config.tariff_base_cost or 10000
    local embargo_base = config.embargo_base_cost or 25000

    return {
        actor_score = actor_score,
        target_score = target_score,
        ratio = ratio,
        can_tariff = can_tariff,
        can_embargo = can_embargo,
        tariff_cost = PowerScore.enforcementCost(actor_score, target_score, tariff_base),
        embargo_cost = PowerScore.enforcementCost(actor_score, target_score, embargo_base),
    }
end

return PowerScore
