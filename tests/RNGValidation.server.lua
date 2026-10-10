--!strict
-- Server Script beside RNGModule.
local RNG = require(script.Parent:WaitForChild("RNGModule"))

local function mustReject(config)
    assert(not pcall(RNG.new, config), "Malformed engine configuration accepted")
end

mustReject({Rarities = {}})
mustReject({Rarities = {Common = {Tier = 1, Base = -1}}})
mustReject({Rarities = {Common = {Tier = 1.5, Base = 0.5}}})
mustReject({Rarities = {Common = {Tier = 1, Base = math.huge}}})

local engine = RNG.new({
    Rarities = {
        Common = {Tier = 1, Base = 0},
        Epic = {Tier = 4, Base = 0},
    },
})
local state = RNG.newState()
local reward = engine:roll(state)
assert(reward ~= nil and reward.Rarity == "Common", "Fallback selection failed")
assert(state.LastRarity == "Common" and state.LastTier == 1, "Fallback state inconsistent")
assert(state.RarityFails.Common == 0 and state.TierFails[1] == 0, "Fallback streak should reset")
assert(state.TotalRolls == 1, "Fallback roll not counted")

assert(not pcall(engine.getExpected, engine, -1), "Negative luck accepted")
assert(not pcall(engine.getChanceText, engine, math.huge), "Infinite luck accepted")
assert(not pcall(engine.getNextRollChances, engine, state, -math.huge), "Invalid luck accepted")
print("RNGModule validation and fallback regression PASS")
