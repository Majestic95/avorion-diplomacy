-- EDE Tariff Calculation
-- Pure math module — no Avorion API calls (testable outside the game)

local Tariffs = {}

--- Calculate the tariff surcharge on a trade transaction.
--- @param base_price number The original transaction price
--- @param tariff_rate number The tariff rate (0.0 to 1.0)
--- @return number surcharge The additional cost due to tariff
function Tariffs.calculateSurcharge(base_price, tariff_rate)
    if base_price <= 0 or tariff_rate <= 0 then
        return 0
    end
    if tariff_rate > 1.0 then
        tariff_rate = 1.0
    end
    return math.floor(base_price * tariff_rate + 0.5)
end

--- Calculate the discounted price from a trade agreement.
--- @param base_price number The original transaction price
--- @param discount_rate number The discount rate (0.0 to 1.0)
--- @return number discounted_price The reduced price
function Tariffs.calculateDiscount(base_price, discount_rate)
    if base_price <= 0 or discount_rate <= 0 then
        return base_price
    end
    if discount_rate > 1.0 then
        discount_rate = 1.0
    end
    return math.floor(base_price * (1 - discount_rate) + 0.5)
end

return Tariffs
