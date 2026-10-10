# RNGModule — rarity rolls and pity logic for Roblox

A standalone Luau rarity engine for simulators, RPG loot tables, and random rewards. Supports configurable rarity tiers, luck modifiers, banner group multipliers, soft/hard pity, currency deductions, streak data, bulk draws, and probability-display helpers.

## Installation

Put `RNGModule.lua` into a Roblox `ModuleScript` named `RNGModule`, for example under `ReplicatedStorage`. Require from a server Script; the server must be authoritative for currency balances and rewards.

```luau
local RNG = require(game:GetService("ReplicatedStorage"):WaitForChild("RNGModule"))

local engine = RNG.new({
    Rarities = {
        Common = {Tier = 1, Base = 0.60},
        Uncommon = {Tier = 2, Base = 0.25},
        Rare = {Tier = 3, Base = 0.10},
        Epic = {Tier = 4, Base = 0.04},
        Legendary = {Tier = 5, Base = 0.01},
    },
    Pity = {
        SoftStart = 50,
        SoftGain = 0.05,
        HardCap = 90,
        HardReward = "Legendary",
    },
})

local state = RNG.newState()
local wallet = {Coins = 1000}
local result, err = engine:roll(state, 1, 10, wallet, "Coins")
if result then
    print(result.Rarity, result.Tier, wallet.Coins)
else
    warn(err)
end
```

## Public methods

| API | Description |
| --- | --- |
| `RNG.new(config)` | Construct a rarity engine; validates nonempty rarities, tiers and weights |
| `RNG.newState(seed?)` | New roll state; optional seed currently calls global `math.randomseed` |
| `engine:roll(state, luck?, cost?, wallet?, key?)` | Roll once; returns result or `nil, "INSUFFICIENT_CURRENCY"` |
| `engine:bulk(state, count, luck?, cost?, wallet?, key?)` | Roll repeatedly; returns rarity counts |
| `engine:getExpected(luck?)` | Base chance plus luck modifier per rarity |
| `engine:getNextRollChances(state, luck?)` | Normalized relative weights for the supplied state |
| `engine:getExpectedRollsFor(state, rarity, luck?)` | Reciprocal of estimated next-roll weight |
| `engine:getExpectedRollsText(state, luck?)` | Human-readable estimates |
| `engine:getChanceText(luck?)` | Human-readable base/luck weights |
| `engine:getDryStreak(state, rarity)` | Miss counter for a named rarity |
| `engine:getTierDryStreak(state, tier)` | Miss counter for a tier |
| `engine:getPityText(state)` | Current pity meter |
| `engine:resetState(state)` | Clear roll statistics |

## Correctness maintenance

- Reject malformed or empty rarity definitions at engine creation.
- Reject nonfinite and negative luck values in all probability-reporting helpers.
- Keep `LastRarity`, `LastTier`, and the awarded rarity/tier miss counters in sync when a draw falls back to the lowest rarity. Other pity counters preserve the old semantics.
- Preserve the existing rarity selection and currency APIs, including zero-cost rolls and bulk deduction behavior.

## Important probability limitations

The current picker iterates rarity definitions and compares a shared `math.random()` draw with the sum of weights. It does **not** renormalize every modified weight at selection time. Thus `getNextRollChances()` provides **normalized relative weights**, not necessarily the exact observed roll probabilities if modified weights no longer total 1. Hard pity and the fallback also affect actual frequencies.

A supplied seed currently changes the global Luau random stream via `math.randomseed`, so separate engines should **not** be assumed to have independent seeded generators. This behavior has deliberately not been changed without a versioned migration.

## Type checking, testing, profiling

- The module includes public Luau `export type` aliases for engine configuration and state. It is not yet a fully verified strict module.
- Run `tests/RNGRegression.server.lua` and `tests/RNGValidation.server.lua` in Roblox Studio.
- Profile `roll()` and `bulk()` using representative rarity configurations before accepting a performance claim.
- For compile/type checks use Roblox Studio Script Analysis (which understands Roblox runtime globals). See the official Luau documentation: https://luau.org/typecheck/ and https://luau.org/performance/.

The engine does not enforce client/server authority; keep calls and wallet mutations on the server. Never trust a client to report a winning rarity.
