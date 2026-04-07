-- Test: Tariff Calculations
-- Run with: lua5.1 tools/testrunner.lua tests/economy/tariffs_test.lua

dofile("tests/mocks/avorion.lua")

describe("Tariffs", function()
    local Tariffs

    before_each(function()
        _resetMocks()
        Tariffs = include("economy/tariffs")
    end)

    describe("calculateSurcharge", function()
        it("calculates correct surcharge at 15%", function()
            assert.are.equal(150, Tariffs.calculateSurcharge(1000, 0.15))
        end)

        it("rounds to nearest integer", function()
            assert.are.equal(15, Tariffs.calculateSurcharge(100, 0.149))
        end)

        it("returns 0 for zero price", function()
            assert.are.equal(0, Tariffs.calculateSurcharge(0, 0.15))
        end)

        it("returns 0 for zero rate", function()
            assert.are.equal(0, Tariffs.calculateSurcharge(1000, 0))
        end)

        it("returns 0 for negative price", function()
            assert.are.equal(0, Tariffs.calculateSurcharge(-100, 0.15))
        end)

        it("caps rate at 100%", function()
            assert.are.equal(1000, Tariffs.calculateSurcharge(1000, 1.5))
        end)
    end)

    describe("calculateDiscount", function()
        it("calculates correct discount at 10%", function()
            assert.are.equal(900, Tariffs.calculateDiscount(1000, 0.10))
        end)

        it("returns original price for zero discount", function()
            assert.are.equal(1000, Tariffs.calculateDiscount(1000, 0))
        end)

        it("returns original price for negative discount", function()
            assert.are.equal(1000, Tariffs.calculateDiscount(1000, -0.1))
        end)

        it("caps discount at 100%", function()
            assert.are.equal(0, Tariffs.calculateDiscount(1000, 1.5))
        end)

        it("rounds to nearest integer", function()
            assert.are.equal(850, Tariffs.calculateDiscount(999, 0.149))
        end)
    end)
end)
