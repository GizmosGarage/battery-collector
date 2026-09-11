--[[
	Upgrades  --  ModuleScript, lives in ReplicatedStorage (shared)

	The single source of truth for every shop upgrade: what each level does, and
	what the next level costs. Both the server (Shop, DataCenter, PlayerSpeed,
	BatterySpawner) and the client (ShopUI) require this, so the numbers can
	never disagree.

	Levels are 0-based. Level 0 = the base value, no purchases made.

	Four upgrades competing for the same Cash is the whole point: Speed and
	Capacity make you better at COLLECTING; Efficiency and Cash make you better
	at CASHING OUT -- and now pull directly against each other: Cash pays more
	but makes the data center draw more power per second, Efficiency stretches
	how much usable power each battery you dump actually delivers.
--]]

local Upgrades = {}

-- Display / iteration order for the shop UI.
Upgrades.order = { "Speed", "Capacity", "Efficiency", "Cash" }

-- The mAh a single AAA (commonest) battery is worth. BatterySpawner scales every
-- other size up from this by the same RARITY_FALLOFF it uses for spawn odds
-- (AAA 500 / AA 1500 / C 4500 / D 13500), and the data center's base power need
-- (below) is anchored to this SAME number -- so "a battery's worth of power"
-- means the same thing everywhere it's used, not two numbers that happen to match.
Upgrades.BASE_BATTERY_MAH = 500

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

	Efficiency = {
		name = "Power conversion efficiency",
		base = 1,        -- multiplier on the reserve a dumped battery delivers, at level 0 (no bonus)
		perLevel = 0.2,  -- +20% more usable reserve per level
		unit = "x",
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
-- more power. Anchored so the BASE (level 0) need is exactly one AAA battery's
-- worth of power per second -- "the data center burns a battery a second just to
-- stay on." DataCenter.server.lua actually enforces this against a real power
-- reserve (see there); this is also shown on the DataCenter sign so the number
-- is visible before it bites.
local CASH_POWER_RATIO = Upgrades.BASE_BATTERY_MAH / Upgrades.defs.Cash.base   -- mAh/sec of draw per 1 Cash/sec of payout

function Upgrades.powerNeeded(cashLevel)
	return Upgrades.effect("Cash", cashLevel) * CASH_POWER_RATIO
end

return Upgrades
