--!strict
-- Place as a server Script beside RNGModule.
local RNG = require(script.Parent:WaitForChild("RNGModule"))
local engine = RNG.new({
    Rarities = {
        Common = {Tier = 1, Base = 0.9},
        ["Very Rare"] = {Tier = 2, Base = 0.1},
    },
    Pity = {SoftGain = 0.05},
})
local state = RNG.newState()
local cash = {Coins = 0}
local before = state.TotalRolls
local result, err = engine:roll(state, 1, 5, cash, "Coins")
assert(result == nil and err == "INSUFFICIENT_CURRENCY", "Unpaid rolls must not award a rarity")
assert(state.TotalRolls == before and cash.Coins == 0, "Unpaid roll mutated state")
local ok = pcall(engine.roll, engine, state, 1, -5, cash, "Coins")
assert(not ok, "Negative cost was accepted")
cash.Coins = 20
local paid = engine:roll(state, 1, 5, cash, "Coins")
assert(paid ~= nil and cash.Coins == 15 and state.TotalRolls == before + 1, "Paid roll failed")
local bulkResults = engine:bulk(state, 2, 1, 5, cash, "Coins")
assert(cash.Coins == 5, "Bulk cost accounting failed")
local total = 0
for _, count in pairs(bulkResults) do total += count end
assert(total == 2, "Bulk roll count mismatch")
assert(not pcall(engine.bulk, engine, state, -1), "Negative bulk roll count accepted")
assert(string.find(engine:getChanceText(), "Very Rare:", 1, true), "Rarity names with spaces failed")
assert(string.find(engine:getExpectedRollsText(state), "Very Rare:", 1, true), "Expected roll text failed")
print("RNGModule currency/text regression PASS: 8 cases")
