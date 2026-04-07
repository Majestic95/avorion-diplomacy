-- EDE Trade Agreement Manager
-- Pure logic module — no Avorion API calls (testable outside the game)
--
-- Manages bilateral trade agreements with asymmetric discount rates.
-- Flow: propose → accept/decline → active → cancel

package.path = package.path .. ";data/scripts/lib/?.lua"

local Tariffs = include("economy/tariffs")
local Persistence = include("util/persistence")

local AgreementManager = {}

AgreementManager.Config = {
    DEFAULT_DISCOUNT = 0.10,  -- 10% default discount
    MAX_DISCOUNT = 0.30,      -- 30% max discount
    MIN_DISCOUNT = 0.01,      -- 1% min discount
    STORAGE_PREFIX = "agreement",
    INDEX_KEY = "agreement_index",
    PROPOSAL_PREFIX = "agreement_proposal",
    PROPOSAL_INDEX_KEY = "agreement_proposal_index",
}

AgreementManager.Status = {
    PROPOSED = "proposed",
    ACTIVE = "active",
}

--- Clamp a discount rate to valid range.
--- @param discount number|nil
--- @return number
function AgreementManager.clampDiscount(discount)
    discount = discount or AgreementManager.Config.DEFAULT_DISCOUNT
    if discount < AgreementManager.Config.MIN_DISCOUNT then
        return AgreementManager.Config.MIN_DISCOUNT
    end
    if discount > AgreementManager.Config.MAX_DISCOUNT then
        return AgreementManager.Config.MAX_DISCOUNT
    end
    return discount
end

--- Propose a trade agreement.
--- @param store table Persistence store
--- @param proposer number Proposer faction index
--- @param target number Target faction index
--- @param proposer_discount number Discount the proposer offers to the target
--- @param target_discount number Discount the proposer requests from the target
--- @param timestamp number Current game time
--- @return boolean success
--- @return string|nil error
function AgreementManager.propose(store, proposer, target, proposer_discount, target_discount, timestamp)
    if proposer == target then
        return false, "Cannot propose agreement with yourself"
    end

    -- Check for existing active agreement
    local existing = AgreementManager.getActive(store, proposer, target)
    if existing then
        return false, "Active agreement already exists"
    end

    -- Check for existing pending proposal in either direction
    local pending = AgreementManager.getProposal(store, proposer, target)
    if pending then
        return false, "Pending proposal already exists"
    end
    pending = AgreementManager.getProposal(store, target, proposer)
    if pending then
        return false, "Pending proposal already exists from target"
    end

    proposer_discount = AgreementManager.clampDiscount(proposer_discount)
    target_discount = AgreementManager.clampDiscount(target_discount)

    local proposal = {
        proposer = proposer,
        target = target,
        proposer_discount = proposer_discount, -- what proposer gives
        target_discount = target_discount,      -- what proposer wants
        proposed_at = timestamp,
        status = AgreementManager.Status.PROPOSED,
    }

    local key = AgreementManager.Config.PROPOSAL_PREFIX .. "_" .. proposer .. "_" .. target
    Persistence.save(store, key, proposal)
    AgreementManager._addToProposalIndex(store, proposer, target)

    return true, nil
end

--- Accept a pending proposal. Creates an active agreement.
--- @param store table Persistence store
--- @param proposer number Original proposer faction index
--- @param acceptor number Accepting faction index (must be the target)
--- @param timestamp number Current game time
--- @return boolean success
--- @return string|nil error
function AgreementManager.accept(store, proposer, acceptor, timestamp)
    local proposal = AgreementManager.getProposal(store, proposer, acceptor)
    if not proposal then
        return false, "No pending proposal found"
    end
    if proposal.target ~= acceptor then
        return false, "Only the target can accept"
    end

    -- Create active agreement (bilateral, stored with sorted keys)
    local agreement = {
        faction_a = math.min(proposer, acceptor),
        faction_b = math.max(proposer, acceptor),
        -- Discounts keyed by faction index for easy lookup
        discounts = {},
        accepted_at = timestamp,
        proposed_at = proposal.proposed_at,
        status = AgreementManager.Status.ACTIVE,
    }
    -- The proposer's discount is what they GIVE to the target
    agreement.discounts[tostring(proposer)] = proposal.proposer_discount
    -- The target's discount is what the proposer REQUESTED from them
    agreement.discounts[tostring(acceptor)] = proposal.target_discount

    -- Save active agreement
    local a = agreement.faction_a
    local b = agreement.faction_b
    local key = AgreementManager.Config.STORAGE_PREFIX .. "_" .. a .. "_" .. b
    Persistence.save(store, key, agreement)
    AgreementManager._addToIndex(store, a, b)

    -- Remove proposal
    AgreementManager._removeProposal(store, proposer, acceptor)

    return true, nil
end

--- Decline a pending proposal.
--- @param store table Persistence store
--- @param proposer number Original proposer
--- @param decliner number Declining faction (must be the target)
--- @return boolean success
function AgreementManager.decline(store, proposer, decliner)
    local proposal = AgreementManager.getProposal(store, proposer, decliner)
    if not proposal then
        return false
    end
    AgreementManager._removeProposal(store, proposer, decliner)
    return true
end

--- Get a pending proposal (directional).
--- @param store table Persistence store
--- @param proposer number Proposer faction index
--- @param target number Target faction index
--- @return table|nil proposal
function AgreementManager.getProposal(store, proposer, target)
    local key = AgreementManager.Config.PROPOSAL_PREFIX .. "_" .. proposer .. "_" .. target
    return Persistence.load(store, key)
end

--- Get an active agreement between two factions (order-independent).
--- @param store table Persistence store
--- @param faction_a number
--- @param faction_b number
--- @return table|nil agreement
function AgreementManager.getActive(store, faction_a, faction_b)
    local a = math.min(faction_a, faction_b)
    local b = math.max(faction_a, faction_b)
    local key = AgreementManager.Config.STORAGE_PREFIX .. "_" .. a .. "_" .. b
    local agreement = Persistence.load(store, key)
    if agreement and agreement.status == AgreementManager.Status.ACTIVE then
        return agreement
    end
    return nil
end

--- Get the discount rate a faction receives from an active agreement.
--- @param store table Persistence store
--- @param buyer_faction number The faction buying (receiving the discount)
--- @param seller_faction number The other faction in the agreement
--- @return number discount The discount rate (0 if no agreement)
function AgreementManager.getDiscount(store, buyer_faction, seller_faction)
    local agreement = AgreementManager.getActive(store, buyer_faction, seller_faction)
    if not agreement then
        return 0
    end
    -- The discount the buyer receives is what the seller GIVES
    local seller_key = tostring(seller_faction)
    return agreement.discounts[seller_key] or 0
end

--- Calculate the discounted price for a transaction.
--- @param store table Persistence store
--- @param buyer_faction number
--- @param seller_faction number
--- @param price number Original price
--- @return number discounted_price
--- @return number discount_rate
function AgreementManager.calculateDiscount(store, buyer_faction, seller_faction, price)
    local rate = AgreementManager.getDiscount(store, buyer_faction, seller_faction)
    if rate <= 0 then
        return price, 0
    end
    return Tariffs.calculateDiscount(price, rate), rate
end

--- Cancel an active agreement. Either party can cancel.
--- @param store table Persistence store
--- @param faction_a number
--- @param faction_b number
--- @return boolean success
function AgreementManager.cancel(store, faction_a, faction_b)
    local a = math.min(faction_a, faction_b)
    local b = math.max(faction_a, faction_b)
    local key = AgreementManager.Config.STORAGE_PREFIX .. "_" .. a .. "_" .. b
    local existing = Persistence.load(store, key)
    if not existing then
        return false
    end
    Persistence.delete(store, key)
    AgreementManager._removeFromIndex(store, a, b)
    return true
end

--- Get all active agreement pairs.
--- @param store table Persistence store
--- @return table pairs Array of {faction_a, faction_b}
function AgreementManager.getAllActive(store)
    return Persistence.load(store, AgreementManager.Config.INDEX_KEY) or {}
end

--- Get all pending proposal pairs.
--- @param store table Persistence store
--- @return table pairs Array of {proposer, target}
function AgreementManager.getAllProposals(store)
    return Persistence.load(store, AgreementManager.Config.PROPOSAL_INDEX_KEY) or {}
end

-- Internal index management

function AgreementManager._addToIndex(store, a, b)
    local index = Persistence.load(store, AgreementManager.Config.INDEX_KEY) or {}
    for _, pair in ipairs(index) do
        if pair.faction_a == a and pair.faction_b == b then return end
    end
    index[#index + 1] = { faction_a = a, faction_b = b }
    Persistence.save(store, AgreementManager.Config.INDEX_KEY, index)
end

function AgreementManager._removeFromIndex(store, a, b)
    local index = Persistence.load(store, AgreementManager.Config.INDEX_KEY) or {}
    local new = {}
    for _, pair in ipairs(index) do
        if not (pair.faction_a == a and pair.faction_b == b) then
            new[#new + 1] = pair
        end
    end
    Persistence.save(store, AgreementManager.Config.INDEX_KEY, new)
end

function AgreementManager._addToProposalIndex(store, proposer, target)
    local index = Persistence.load(store, AgreementManager.Config.PROPOSAL_INDEX_KEY) or {}
    for _, pair in ipairs(index) do
        if pair.proposer == proposer and pair.target == target then return end
    end
    index[#index + 1] = { proposer = proposer, target = target }
    Persistence.save(store, AgreementManager.Config.PROPOSAL_INDEX_KEY, index)
end

function AgreementManager._removeProposal(store, proposer, target)
    local key = AgreementManager.Config.PROPOSAL_PREFIX .. "_" .. proposer .. "_" .. target
    Persistence.delete(store, key)
    -- Remove from proposal index
    local index = Persistence.load(store, AgreementManager.Config.PROPOSAL_INDEX_KEY) or {}
    local new = {}
    for _, pair in ipairs(index) do
        if not (pair.proposer == proposer and pair.target == target) then
            new[#new + 1] = pair
        end
    end
    Persistence.save(store, AgreementManager.Config.PROPOSAL_INDEX_KEY, new)
end

return AgreementManager
