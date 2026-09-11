--[[
	Upgrades  --  ModuleScript, lives in ReplicatedStorage (shared)

	The single source of truth for the two shop upgrades: what each level does,
	and what the next level costs. Both the server (Shop, DataCenter) and the
	client (ShopUI) require this, so the numbers can never disagree.

	Levels are 0-based. Level 0 = the base value, no purchases made.
--]]

local Upgrades = {}

Upgrades.defs = {
	Seconds = {
		name = "Run time per 1000 mAh",
		base = 2,        -- seconds of data-center runtime each 1000 mAh dumped buys, at level 0
		perLevel = 0.5,  -- each level adds this much
		unit = "s",
		baseCost = 50,   -- Cash to go from level 0 -> 1
		growth = 1.5,    -- cost multiplies by this each level (exponential)
	},

	Cash = {
		name = "Cash per second",
		base = 5,        -- Cash paid each second while the data center runs, at level 0
		perLevel = 2,
		unit = "/s",
		baseCost = 50,
		growth = 1.5,
	},
}

-- The gameplay value this upgrade produces at a given level.
function Upgrades.effect(id, level)
	local d = Upgrades.defs[id]
	return d.base + level * d.perLevel
end

-- The Cash price to buy the NEXT level (i.e. to go from `level` to `level + 1`).
-- Grows exponentially: baseCost, baseCost*growth, baseCost*growth^2, ...
function Upgrades.cost(id, level)
	local d = Upgrades.defs[id]
	return math.floor(d.baseCost * (d.growth ^ level))
end

-- Pretty-print an effect value with its unit (seconds get one decimal).
function Upgrades.formatEffect(id, value)
	local d = Upgrades.defs[id]
	if d.unit == "s" then
		return string.format("%.1f%s", value, d.unit)
	end
	return string.format("%d%s", value, d.unit)
end

return Upgrades
