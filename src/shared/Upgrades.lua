--[[
	Upgrades  --  ModuleScript, lives in ReplicatedStorage (shared)

	The single source of truth for every shop upgrade: what each level does, and
	what the next level costs. Both the server (Shop, DataCenter, PlayerSpeed,
	BatterySpawner) and the client (ShopUI) require this, so the numbers can
	never disagree.

	Levels are 0-based. Level 0 = the base value, no purchases made.

	Four upgrades competing for the same Cash is the whole point: Speed and
	Capacity make you better at COLLECTING; Seconds and Cash make you better at
	CASHING OUT. Every purchase is Cash you didn't spend on the other three.
--]]

local Upgrades = {}

-- Display / iteration order for the shop UI.
Upgrades.order = { "Speed", "Capacity", "Seconds", "Cash" }

Upgrades.defs = {
	Speed = {
		name = "Walk speed",
		base = 4,        -- studs/second at level 0 (Roblox default is 16 -- this is a slow trudge)
		perLevel = 1.5,
		unit = " spd",
		decimal = true,  -- show one decimal place
		baseCost = 50,   -- Cash to go from level 0 -> 1
		growth = 1.5,    -- cost multiplies by this each level (exponential)
	},

	Capacity = {
		name = "Batteries you can carry",
		base = 5,        -- battery SLOTS at level 0, regardless of size
		perLevel = 1,
		unit = "",
		baseCost = 50,
		growth = 1.5,
	},

	Seconds = {
		name = "Run time per 1000 mAh",
		base = 2,        -- seconds of data-center runtime each 1000 mAh dumped buys, at level 0
		perLevel = 0.5,
		unit = "s",
		decimal = true,
		baseCost = 50,
		growth = 1.5,
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

-- Pretty-print an effect value with its unit.
function Upgrades.formatEffect(id, value)
	local d = Upgrades.defs[id]
	if d.decimal then
		return string.format("%.1f%s", value, d.unit)
	end
	return string.format("%d%s", value, d.unit)
end

-- How much power (mAh/sec) the data center's GPUs need to sustain a given Cash
-- upgrade level -- each level is another GPU unit added, and more GPUs need
-- more power. Currently a READOUT (shown on the DataCenter sign) so upgrading
-- Cash visibly costs something even though nothing enforces it yet.
local CASH_POWER_RATIO = 2   -- mAh/sec of draw per 1 Cash/sec of payout

function Upgrades.powerNeeded(cashLevel)
	return Upgrades.effect("Cash", cashLevel) * CASH_POWER_RATIO
end

return Upgrades
