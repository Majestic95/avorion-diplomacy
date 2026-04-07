-- EDE Tariff Manager
-- Pure logic module — no Avorion API calls (testable outside the game)
--
-- Manages the full tariff lifecycle: declare, query, enforce cost, collect revenue, remove.
-- All state is persisted via the Persistence module.

package.path = package.path .. ";data/scripts/lib/?.lua"

local PowerScore = include("economy/power_score")
local Tariffs = include("economy/tariffs")
local Persistence = include("util/persistence")

local TariffManager = {}

-- Constants
TariffManager.Config = {
    BASE_COST = 10000,       -- credits per game-day to enforce a tariff
    DEFAULT_RATE = 0.15,     -- 15% default tariff rate
    MAX_RATE = 0.50,         -- 50% maximum tariff rate
    MIN_RATE = 0.01,         -- 1% minimum tariff rate
    GRACE_DAYS = 1,          -- game-days before enforcement lapses on missed payment
    STORAGE_PREFIX = "tariff", -- persistence key prefix
    INDEX_KEY = "tariff_index", -- key for the master index of all active tariffs
}

--- Create a tariff declaration record.
--- @param imposer_index number Faction index of the imposer
--- @param target_index number Faction index of the target
--- @param rate number Tariff rate (0.01 to 0.50)
--- @param imposer_score number Imposer's power score at time of declaration
--- @param target_score number Target's power score at time of declaration
--- @param timestamp number Game time when declared
--- @return table tariff The tariff record
local function createTariffRecord(imposer_index, target_index, rate, imposer_score, target_score, timestamp)
    return {
        imposer = imposer_index,
        target = target_index,
        rate = rate,
        imposer_score = imposer_score,
        target_score = target_score,
        declared_at = timestamp,
        last_paid_at = timestamp,
        missed_payments = 0,
        active = true,
        total_revenue = 0,
    }
end

--- Validate and clamp a tariff rate.
--- @param rate number|nil The requested rate
--- @return number rate The clamped rate
function TariffManager.clampRate(rate)
    rate = rate or TariffManager.Config.DEFAULT_RATE
    if rate < TariffManager.Config.MIN_RATE then
        return TariffManager.Config.MIN_RATE
    end
    if rate > TariffManager.Config.MAX_RATE then
        return TariffManager.Config.MAX_RATE
    end
    return rate
end

--- Attempt to declare a tariff.
--- @param store table Persistence store (e.g., Galaxy())
--- @param imposer_index number Faction imposing the tariff
--- @param target_index number Faction being tariffed
--- @param imposer_score number Imposer's power score
--- @param target_score number Target's power score
--- @param rate number|nil Tariff rate (defaults to 15%)
--- @param timestamp number Current game time
--- @return boolean success Whether the tariff was declared
--- @return string|nil error Error message if failed
function TariffManager.declare(store, imposer_index, target_index, imposer_score, target_score, rate, timestamp)
    if imposer_index == target_index then
        return false, "Cannot impose tariff on yourself"
    end

    -- Check enforcement threshold
    local can_enforce, _ = PowerScore.canEnforce(imposer_score, target_score, "tariff")
    if not can_enforce then
        return false, "Insufficient power to enforce tariff"
    end

    -- Check for existing tariff from this imposer on this target
    local existing = TariffManager.get(store, imposer_index, target_index)
    if existing and existing.active then
        return false, "Tariff already active against this faction"
    end

    rate = TariffManager.clampRate(rate)
    local record = createTariffRecord(imposer_index, target_index, rate, imposer_score, target_score, timestamp)

    -- Store the tariff (directional: imposer→target, NOT bilateral)
    local key = TariffManager.Config.STORAGE_PREFIX .. "_" .. imposer_index .. "_" .. target_index
    Persistence.save(store, key, record)

    -- Update the master index
    TariffManager._addToIndex(store, imposer_index, target_index)

    return true, nil
end

--- Get a tariff record between two specific factions (directional).
--- @param store table Persistence store
--- @param imposer_index number The faction that imposed the tariff
--- @param target_index number The faction being tariffed
--- @return table|nil tariff The tariff record, or nil if none exists
function TariffManager.get(store, imposer_index, target_index)
    local key = TariffManager.Config.STORAGE_PREFIX .. "_" .. imposer_index .. "_" .. target_index
    return Persistence.load(store, key)
end

--- Get the effective tariff rate a buyer/seller pair faces.
--- Checks both directions (A tariffed B, or B tariffed A) and returns the highest.
--- @param store table Persistence store
--- @param faction_a number First faction index
--- @param faction_b number Second faction index
--- @return number rate The effective tariff rate (0 if no tariff)
--- @return table|nil tariff The active tariff record (highest rate)
function TariffManager.getEffectiveRate(store, faction_a, faction_b)
    local tariff_ab = TariffManager.get(store, faction_a, faction_b)
    local tariff_ba = TariffManager.get(store, faction_b, faction_a)

    local rate_ab = (tariff_ab and tariff_ab.active) and tariff_ab.rate or 0
    local rate_ba = (tariff_ba and tariff_ba.active) and tariff_ba.rate or 0

    if rate_ab >= rate_ba then
        return rate_ab, tariff_ab
    else
        return rate_ba, tariff_ba
    end
end

--- Calculate the tariff surcharge on a transaction.
--- @param store table Persistence store
--- @param buyer_faction number Buyer's faction index
--- @param seller_faction number Seller's faction index
--- @param price number Transaction price
--- @return number surcharge The tariff surcharge amount (0 if no tariff)
--- @return number rate The applied rate
function TariffManager.calculateSurcharge(store, buyer_faction, seller_faction, price)
    local rate, _ = TariffManager.getEffectiveRate(store, buyer_faction, seller_faction)
    if rate <= 0 then
        return 0, 0
    end
    return Tariffs.calculateSurcharge(price, rate), rate
end

--- Remove a tariff.
--- @param store table Persistence store
--- @param imposer_index number The faction that imposed the tariff
--- @param target_index number The faction being tariffed
--- @return boolean success Whether a tariff was found and removed
function TariffManager.remove(store, imposer_index, target_index)
    local existing = TariffManager.get(store, imposer_index, target_index)
    if not existing then
        return false
    end

    local key = TariffManager.Config.STORAGE_PREFIX .. "_" .. imposer_index .. "_" .. target_index
    Persistence.delete(store, key)
    TariffManager._removeFromIndex(store, imposer_index, target_index)
    return true
end

--- Calculate the enforcement cost for a tariff.
--- @param imposer_score number Imposer's current power score
--- @param target_score number Target's current power score
--- @param tariff_rate number|nil The tariff rate (defaults to 0.15)
--- @return number cost Credits per game-day cycle (3 real hours)
function TariffManager.getEnforcementCost(imposer_score, target_score, tariff_rate)
    return PowerScore.tariffCost(imposer_score, target_score, tariff_rate or TariffManager.Config.DEFAULT_RATE)
end

--- Process a payment cycle for a tariff. Returns whether the tariff survives.
--- @param store table Persistence store
--- @param imposer_index number Imposer faction index
--- @param target_index number Target faction index
--- @param imposer_balance number Imposer's current credit balance
--- @param imposer_score number Imposer's current power score
--- @param target_score number Target's current power score
--- @param timestamp number Current game time
--- @return boolean active Whether the tariff is still active
--- @return number cost The enforcement cost charged (0 if lapsed)
function TariffManager.processPaymentCycle(store, imposer_index, target_index,
                                            imposer_balance, imposer_score, target_score, timestamp)
    local tariff = TariffManager.get(store, imposer_index, target_index)
    if not tariff or not tariff.active then
        return false, 0
    end

    local cost = TariffManager.getEnforcementCost(imposer_score, target_score, tariff.rate)

    if imposer_balance >= cost then
        -- Successful payment
        tariff.last_paid_at = timestamp
        tariff.missed_payments = 0
        local key = TariffManager.Config.STORAGE_PREFIX .. "_" .. imposer_index .. "_" .. target_index
        Persistence.save(store, key, tariff)
        return true, cost
    else
        -- Missed payment
        tariff.missed_payments = (tariff.missed_payments or 0) + 1
        if tariff.missed_payments > TariffManager.Config.GRACE_DAYS then
            -- Enforcement lapses
            TariffManager.remove(store, imposer_index, target_index)
            return false, 0
        else
            -- Grace period
            local key = TariffManager.Config.STORAGE_PREFIX .. "_" .. imposer_index .. "_" .. target_index
            Persistence.save(store, key, tariff)
            return true, 0
        end
    end
end

--- Record revenue from a tariff surcharge.
--- @param store table Persistence store
--- @param imposer_index number Imposer faction index
--- @param target_index number Target faction index
--- @param amount number Revenue amount
function TariffManager.recordRevenue(store, imposer_index, target_index, amount)
    local tariff = TariffManager.get(store, imposer_index, target_index)
    if tariff and tariff.active then
        tariff.total_revenue = (tariff.total_revenue or 0) + amount
        local key = TariffManager.Config.STORAGE_PREFIX .. "_" .. imposer_index .. "_" .. target_index
        Persistence.save(store, key, tariff)
    end
end

--- Get all active tariff pairs from the master index.
--- @param store table Persistence store
--- @return table pairs Array of {imposer, target} pairs
function TariffManager.getAllActive(store)
    local index = Persistence.load(store, TariffManager.Config.INDEX_KEY)
    return index or {}
end

-- Internal: add a tariff pair to the master index
function TariffManager._addToIndex(store, imposer_index, target_index)
    local index = Persistence.load(store, TariffManager.Config.INDEX_KEY) or {}
    -- Check for duplicates
    for _, pair in ipairs(index) do
        if pair.imposer == imposer_index and pair.target == target_index then
            return
        end
    end
    index[#index + 1] = { imposer = imposer_index, target = target_index }
    Persistence.save(store, TariffManager.Config.INDEX_KEY, index)
end

-- Internal: remove a tariff pair from the master index
function TariffManager._removeFromIndex(store, imposer_index, target_index)
    local index = Persistence.load(store, TariffManager.Config.INDEX_KEY) or {}
    local new_index = {}
    for _, pair in ipairs(index) do
        if not (pair.imposer == imposer_index and pair.target == target_index) then
            new_index[#new_index + 1] = pair
        end
    end
    Persistence.save(store, TariffManager.Config.INDEX_KEY, new_index)
end

return TariffManager
