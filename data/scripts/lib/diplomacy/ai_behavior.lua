-- EDE AI Faction Diplomatic Behavior
-- Pure logic module — no Avorion API calls (testable outside the game)
--
-- Decides how AI factions respond to diplomatic actions against them.
-- Behavior is driven by faction archetype and the severity of the action.

package.path = package.path .. ";data/scripts/lib/?.lua"

local AIBehavior = {}

-- Response types the AI can choose
AIBehavior.Response = {
    IGNORE = "ignore",               -- Do nothing
    COUNTER_TARIFF = "counter_tariff", -- Impose retaliatory tariff
    BREAK_AGREEMENT = "break_agreement", -- Cancel existing trade agreement
    RELATION_DROP = "relation_drop",   -- Decrease relations (toward war)
    PROPOSE_AGREEMENT = "propose_agreement", -- Offer a trade agreement
}

-- Archetype personality profiles
-- retaliation_chance: probability of retaliating to a tariff (0.0-1.0)
-- escalation_speed: how quickly they go from tariff to embargo/war (1=slow, 3=fast)
-- forgiveness: how quickly they return to normal after action is removed (1=slow, 3=fast)
-- trade_affinity: likelihood of proposing trade agreements (0.0-1.0)
AIBehavior.Profiles = {
    Corporate = {
        retaliation_chance = 0.70,
        escalation_speed = 1,
        forgiveness = 3,
        trade_affinity = 0.80,
    },
    Militaristic = {
        retaliation_chance = 0.95,
        escalation_speed = 3,
        forgiveness = 1,
        trade_affinity = 0.20,
    },
    Traditional = {
        retaliation_chance = 0.60,
        escalation_speed = 2,
        forgiveness = 1,
        trade_affinity = 0.50,
    },
    Independent = {
        retaliation_chance = 0.50,
        escalation_speed = 1,
        forgiveness = 2,
        trade_affinity = 0.40,
    },
    Religious = {
        retaliation_chance = 0.65,
        escalation_speed = 2,
        forgiveness = 1,
        trade_affinity = 0.35,
    },
    Sect = {
        retaliation_chance = 0.80,
        escalation_speed = 2,
        forgiveness = 1,
        trade_affinity = 0.15,
    },
    Alliance = {
        retaliation_chance = 0.55,
        escalation_speed = 1,
        forgiveness = 2,
        trade_affinity = 0.60,
    },
    Vanilla = {
        retaliation_chance = 0.50,
        escalation_speed = 1,
        forgiveness = 2,
        trade_affinity = 0.40,
    },
}

--- Get the personality profile for an archetype.
--- @param archetype string The faction archetype name
--- @return table profile The personality profile (defaults to Vanilla)
function AIBehavior.getProfile(archetype)
    return AIBehavior.Profiles[archetype] or AIBehavior.Profiles.Vanilla
end

--- Decide how an AI faction responds to being tariffed.
--- @param archetype string The AI faction's archetype
--- @param roll number Random value 0.0-1.0 (injected for testability)
--- @param has_existing_agreement boolean Whether a trade agreement exists with the imposer
--- @return string response One of AIBehavior.Response values
--- @return table details Additional context for the response
function AIBehavior.respondToTariff(archetype, roll, has_existing_agreement)
    local profile = AIBehavior.getProfile(archetype)

    -- First: if we have a trade agreement, break it
    if has_existing_agreement then
        return AIBehavior.Response.BREAK_AGREEMENT, {
            reason = "retaliatory_break",
        }
    end

    -- Then: decide whether to retaliate with counter-tariff
    if roll <= profile.retaliation_chance then
        return AIBehavior.Response.COUNTER_TARIFF, {
            rate = 0.15, -- match the standard rate
            reason = "retaliation",
        }
    end

    -- Otherwise: just drop relations
    return AIBehavior.Response.RELATION_DROP, {
        amount = -10000 * profile.escalation_speed,
        reason = "displeasure",
    }
end

--- Decide how an AI faction responds to being embargoed.
--- Embargoes are more severe — AI always retaliates.
--- @param archetype string The AI faction's archetype
--- @param roll number Random value 0.0-1.0
--- @return string response
--- @return table details
function AIBehavior.respondToEmbargo(archetype, roll)
    local profile = AIBehavior.getProfile(archetype)

    -- Embargoes always cause a major relation drop
    local relation_drop = -30000 * profile.escalation_speed

    -- Militaristic factions may escalate toward war
    if profile.escalation_speed >= 3 and roll <= 0.50 then
        return AIBehavior.Response.RELATION_DROP, {
            amount = -80000, -- near war threshold
            reason = "embargo_war_escalation",
        }
    end

    -- Counter-tariff is the minimum response
    return AIBehavior.Response.COUNTER_TARIFF, {
        rate = 0.30, -- punitive rate
        reason = "embargo_retaliation",
        relation_drop = relation_drop,
    }
end

--- Decide whether an AI faction should proactively propose a trade agreement.
--- Called periodically (e.g., once per game-day) for each AI faction.
--- @param archetype string The AI faction's archetype
--- @param relation_level number Current relation level with the target (-100000 to 100000)
--- @param roll number Random value 0.0-1.0
--- @return boolean should_propose
--- @return table|nil details Proposal details if should_propose is true
function AIBehavior.shouldProposeAgreement(archetype, relation_level, roll)
    local profile = AIBehavior.getProfile(archetype)

    -- Only propose if relations are positive
    if relation_level < 10000 then
        return false, nil
    end

    -- Higher relations = higher chance, scaled by trade affinity
    local relation_factor = math.min(relation_level / 100000, 1.0)
    local chance = profile.trade_affinity * relation_factor * 0.10 -- max ~8% per check

    if roll <= chance then
        local discount = 0.05 + (relation_factor * 0.10) -- 5-15% based on relations
        return true, {
            discount = math.floor(discount * 100 + 0.5) / 100, -- round to 2dp
            reason = "proactive_trade",
        }
    end

    return false, nil
end

--- Decide whether an AI faction should proactively impose a tariff.
--- Called periodically for each AI faction.
--- @param archetype string The AI faction's archetype
--- @param relation_level number Current relation level with the target
--- @param roll number Random value 0.0-1.0
--- @return boolean should_tariff
--- @return table|nil details
function AIBehavior.shouldImposeTariff(archetype, relation_level, roll)
    local profile = AIBehavior.getProfile(archetype)

    -- Only impose tariffs on factions they dislike
    if relation_level > -10000 then
        return false, nil
    end

    -- Worse relations = higher chance
    local hostility = math.min(math.abs(relation_level) / 100000, 1.0)
    local chance = hostility * 0.05 * profile.escalation_speed -- max ~15% per check

    if roll <= chance then
        local rate = 0.10 + (hostility * 0.15) -- 10-25% based on hostility
        return true, {
            rate = math.floor(rate * 100 + 0.5) / 100,
            reason = "proactive_hostility",
        }
    end

    return false, nil
end

return AIBehavior
