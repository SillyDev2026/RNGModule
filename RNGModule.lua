local RNG = {}
RNG.__index = RNG

export type RarityName = string
export type RarityDef = {Tier: number, Base: number, Group: string?}
export type RarityTable = {[RarityName]: RarityDef}
export type PityRule = {SoftStart: number?, SoftGain: number?, HardCap: number?, HardReward: RarityName?}
export type BannerRule = {Group: string, Multiplier: number}
export type EngineConfig = {Rarities: RarityTable, Pity: PityRule?, Banners: {BannerRule}?}
export type RNGState = {
	Seed: number?, TotalRolls: number, LastRarity: RarityName?, LastTier: number, Entropy: number,
	BadLuck: number, GlobalFails: number, TierFails: {[number]: number}, RarityFails: {[RarityName]: number},
	PityMeter: number?, PityTargetTiers: {number}?
}
export type RollResult = {Rarity: RarityName, Tier: number}
export type RNGEngine = {
	Rarities: RarityTable, Pity: PityRule?, Banners: {BannerRule},
	roll: (self: RNGEngine, state: RNGState, luck: number?, rollCost: number?, currency: {[string]: number}?, poolName: string?) -> RollResult,
	bulk: (self: RNGEngine, state: RNGState, rolls: number, luck: number?, rollCost: number?, currency: {[string]: number}?, poolName: string?) -> {[RarityName]: number},
	getExpected: (self: RNGEngine, luck: number?) -> {[RarityName]: number},
	getDryStreak: (self: RNGEngine, state: RNGState, rarity: RarityName) -> number,
	getTierDryStreak: (self: RNGEngine, state: RNGState, tier: number) -> number,
	resetState: (self: RNGEngine, state: RNGState) -> (),
	getChanceText: (self: RNGEngine, luck: number?) -> string,
	getNextRollChances: (self: RNGEngine, state: RNGState, luck: number?) -> {[RarityName]: number},
	getExpectedRollsFor: (self: RNGEngine, state: RNGState, rarity: RarityName, luck: number?) -> number,
	getExpectedRollsText: (self: RNGEngine, state: RNGState, luck: number?) -> string,
	getPityText: (self: RNGEngine, state: RNGState) -> string,
}

local function luckModifier(luck: number, tier: number): number
	return math.log(luck + 1) * tier * 0.01
end

local function pityModifier(state: RNGState, tier: number): number
	local fails = state.TierFails[tier] or 0
	return (fails ^ 1.15) * 0.002
end

local function entropyModifier(state: RNGState, tier: number): number
	if tier <= state.LastTier then
		return state.Entropy * 0.4
	end
	return state.Entropy
end

local function bannerModifier(def: RarityDef, banners: {BannerRule}?): number
	if not banners or not def.Group then return 0 end
	for _, banner in ipairs(banners) do
		if banner.Group == def.Group then
			return banner.Multiplier - 1
		end
	end
	return 0
end

function RNG.new(config: EngineConfig): RNGEngine
	assert(config and config.Rarities, "Rarities required")
	local engine: RNGEngine = setmetatable({Rarities = config.Rarities, Pity = config.Pity, Banners = config.Banners or {}}, RNG)
	return engine
end

function RNG.newState(seed: number?): RNGState
	if seed then math.randomseed(seed) end
	return {Seed = seed, TotalRolls = 0, LastRarity = nil, LastTier = 0, Entropy = 0, BadLuck = 0, GlobalFails = 0, TierFails = {}, RarityFails = {}, PityMeter = 0, PityTargetTiers = nil}
end

function RNG:roll(state: RNGState, luck: number?, rollCost: number?, currency: {[string]: number}?, poolName: string?)
	rollCost = rollCost or 0
	if currency and poolName and currency[poolName] then
		if currency[poolName] >= rollCost then
			currency[poolName] = currency[poolName] - rollCost
		else
			warn('Not enough Currnecy to roll for:', poolName)
		end
	end

	local effectiveLuck = luck or 1
	state.TotalRolls += 1

	if state.PityMeter ~= nil then
		local softGain = self.Pity and self.Pity.SoftGain or 0.05
		state.PityMeter = math.clamp(state.PityMeter + softGain, 0, 10)
		if state.PityMeter >= 1 and state.PityTargetTiers then
			local eligible = {}
			for name, def in pairs(self.Rarities) do
				if table.find(state.PityTargetTiers, def.Tier) then table.insert(eligible, name) end
			end
			if #eligible > 0 then
				local chosen = eligible[math.random(1,#eligible)]
				local tier = self.Rarities[chosen].Tier
				state.PityMeter = 0
				state.LastRarity = chosen
				state.LastTier = tier
				state.TierFails[tier] = 0
				state.RarityFails[chosen] = 0
				return {Rarity = chosen, Tier = tier}
			end
		end
	end

	if self.Pity and self.Pity.HardCap and state.GlobalFails >= self.Pity.HardCap then
		local reward = self.Pity.HardReward
		if reward then
			local def = self.Rarities[reward]
			if def then
				state.GlobalFails = 0
				state.BadLuck = 0
				state.Entropy = 0
				state.LastRarity = reward
				state.LastTier = def.Tier
				return {Rarity = reward, Tier = def.Tier}
			end
		end
	end

	local roll = math.random()
	local cumulative = 0
	local chosenName: RarityName? = nil
	local chosenTier = 0

	for name, def in pairs(self.Rarities) do
		local tier = def.Tier
		local prob = def.Base + luckModifier(effectiveLuck, tier) + pityModifier(state, tier) + entropyModifier(state, tier) + bannerModifier(def, self.Banners) - (state.BadLuck or 0) * 0.0003
		if prob > 0 then
			cumulative += prob
			if roll <= cumulative then
				chosenName = name
				chosenTier = tier
				break
			end
		end
	end

	if chosenName then
		state.LastRarity = chosenName
		state.LastTier = chosenTier
		state.Entropy = 0
		state.BadLuck = 0
		state.GlobalFails = 0
		state.TierFails[chosenTier] = 0
		state.RarityFails[chosenName] = 0
		return {Rarity = chosenName, Tier = chosenTier}
	end

	state.GlobalFails += 1
	state.BadLuck += 1
	state.Entropy = math.clamp(state.Entropy + 0.02, 0, 10)
	for name, def in pairs(self.Rarities) do
		local tier = def.Tier
		state.TierFails[tier] = (state.TierFails[tier] or 0) + 1
		state.RarityFails[name] = (state.RarityFails[name] or 0) + 1
	end
	local lowestTier = math.huge
	local lowestName: RarityName = ""
	for name, def in pairs(self.Rarities) do
		if def.Tier < lowestTier then
			lowestTier = def.Tier
			lowestName = name
		end
	end
	return {Rarity = lowestName, Tier = lowestTier ~= math.huge and lowestTier or 0}
end

function RNG:bulk(state: RNGState, rolls: number, luck: number?, rollCost: number?, currency: {[string]: number}?, poolName: string?)
	local results: {[RarityName]: number} = {}
	rollCost = rollCost or 0
	if currency and poolName then
		local balance = currency[poolName] or 0
		local totalCost = rollCost * rolls
		if balance < totalCost then
			warn('Currency is not enough to roll bulk')
			return results
		end
		currency[poolName] = balance - totalCost
	end
	for _=1,rolls do
		local r = self:roll(state, luck, 0, nil, nil)
		results[r.Rarity] = (results[r.Rarity] or 0) + 1
	end
	return results
end

function RNG:getExpected(luck: number?): {[RarityName]: number}
	local effLuck = luck or 1
	local out: {[RarityName]: number} = {}
	for name, def in pairs(self.Rarities) do
		out[name] = def.Base + luckModifier(effLuck, def.Tier)
	end
	return out
end

function RNG:getDryStreak(state: RNGState, rarity: RarityName): number
	return state.RarityFails[rarity] or 0
end

function RNG:getTierDryStreak(state: RNGState, tier: number): number
	return state.TierFails[tier] or 0
end

function RNG:getChanceText(luck: number?): string
	local effLuck = luck or 1
	local lines = {}
	for name, def in pairs(self.Rarities) do
		local prob = def.Base + luckModifier(effLuck, def.Tier) + (self.Pity and self.Pity.SoftGain and pityModifier({TierFails={}, LastTier=0}, def.Tier) or 0) + bannerModifier(def, self.Banners)
		prob = math.max(prob,0)
		table.insert(lines, string.format('%s: %.2f%%', name, prob*100))
	end
	table.sort(lines,function(a,b)
		local tierA = self.Rarities[a:match('^(%w+):')].Tier
		local tierB = self.Rarities[b:match('^(%w+):')].Tier
		return tierA < tierB
	end)
	return table.concat(lines,"\n")
end

function RNG:getNextRollChances(state: RNGState, luck: number?): {[RarityName]: number}
	local effLuck = luck or 1
	local out = {}
	for name, def in pairs(self.Rarities) do
		local tier = def.Tier
		local prob = def.Base + luckModifier(effLuck,tier) + pityModifier(state,tier) + entropyModifier(state,tier) + bannerModifier(def,self.Banners) - (state.BadLuck or 0)*0.0003
		out[name] = math.max(prob,0)
	end
	local total=0
	for _,p in pairs(out) do total+=p end
	if total>0 then for name,p in pairs(out) do out[name]=p/total end end
	return out
end

function RNG:getExpectedRollsFor(state:RNGState, rarity:RarityName, luck:number?): number
	local chances = self:getNextRollChances(state,luck)
	local prob = chances[rarity] or 0
	if prob<=0 then return math.huge end
	return 1/prob
end

function RNG:getExpectedRollsText(state:RNGState,luck:number?): string
	local lines={}
	for name,_ in pairs(self.Rarities) do
		local rolls = self:getExpectedRollsFor(state,name,luck)
		table.insert(lines,string.format("%s: %.1f rolls",name,rolls))
	end
	table.sort(lines,function(a,b)
		local tierA = self.Rarities[a:match("^(%w+):")].Tier
		local tierB = self.Rarities[b:match("^(%w+):")].Tier
		return tierA < tierB
	end)
	return table.concat(lines,"\n")
end

function RNG:getPityText(state:RNGState): string
	return string.format("Pity: %.2f%%",(state.PityMeter or 0)*100)
end

function RNG:resetState(state:RNGState)
	state.TotalRolls = 0
	state.LastRarity = nil
	state.LastTier = 0
	state.Entropy = 0
	state.BadLuck = 0
	state.GlobalFails = 0
	state.TierFails = {}
	state.RarityFails = {}
	state.PityMeter = 0
end

return RNG
