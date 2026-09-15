--[[
	Upgrades  --  ModuleScript, lives in ReplicatedStorage (shared)

	The single source of truth for every LEVEL-based shop upgrade: what each
	level does, and what the next level costs. Both the server (Shop,
	PlayerSpeed, BatterySpawner) and the client (ShopUI) require this, so the
	numbers can never disagree.

	Levels are 0-based. Level 0 = the base value, no purchases made. Both
	Speed and Capacity now stop at `maxLevel` (6) -- Shop.server.lua refuses
	a purchase past it, and ShopUI.client.lua shows "MAX" instead of a price
	once you're there.

	Rather than hand-typing what each of the 6 levels is worth, each def
	gives `base` (level 0) and `top` (the value AT maxLevel), and `perLevel`
	is worked out below as a straight line between them -- change `top` or
	`maxLevel` later and the 6 steps stay evenly spaced automatically,
	always landing EXACTLY on `top` at the last level, instead of drifting
	off it the way a hand-picked `perLevel` could. Speed's `top` (60) is the
	same "top speed" PlayerSpeed.server.lua clamps to -- it reads that value
	back out of here instead of hard-coding its own copy of 60, so the two
	can never disagree about what "top speed" means.

	Speed and Capacity make YOU better at collecting. Cash-per-second used to
	be a level here too (and dumping used to have its own Power Conversion
	level on top of it), but both are GPU hardware and a straight 1:1 dump
	now -- see GPUs.lua and Shop.server.lua's slot system -- so this module
	only covers the two upgrades that are still a simple "buy the next level."
--]]

local Upgrades = {}

-- The shop is THREE platforms -- Speed/Capacity make YOU better at
-- collecting; the GPU catalog and the data center's space/slots (see
-- GPUs.lua) make the DATA CENTER better at cashing out, split across their
-- own two pads so neither panel has to cram a catalog together with the
-- space/slot rows into one scroll. Each entry lives on its own pad (see
-- ShopUI.client.lua's SHOP_PAD_NAMES, in this same order). `title` is what
-- that pad's floating sign says. `gpuCatalogSection`/`slotsSection` tell
-- ShopUI to also build the GPU catalog rows, or the space/slot-unlock +
-- per-slot rows, on that platform -- this module doesn't need to know
-- anything about GPUs itself, just that a shop has room for one of those
-- sections.
Upgrades.shops = {
	{ title = "PLAYER SHOP",       ids = { "Speed", "Capacity" } },
	{ title = "GPU SHOP",          ids = {}, gpuCatalogSection = true },
	{ title = "DATA CENTER SHOP",  ids = {}, slotsSection = true },
}

-- Every upgrade id, in canonical order -- derived from Upgrades.shops
-- (rather than listed a second time) so the two can't drift out of sync.
-- Nothing currently needs this beyond iteration order, but it's here for
-- any future code that wants "all of them, in order" without caring which
-- shop each is on.
Upgrades.order = {}
for _, shop in Upgrades.shops do
	for _, id in shop.ids do
		table.insert(Upgrades.order, id)
	end
end

-- The mAh a single AAA (commonest) battery is worth. BatterySpawner scales
-- every other size up from this by its own RARITY_FALLOFF (AAA 500 / AA
-- 1500 / C 4500 / D 13500) -- "a battery's worth of power" means the same
-- thing everywhere this number is used. How OFTEN each size actually spawns
-- is a separate, per-field setting -- see Fields.lua's `chances`.
Upgrades.BASE_BATTERY_MAH = 500

Upgrades.defs = {
	Speed = {
		name = "Walk speed",
		-- This is your TRUE speed -- it only applies ON THE FIELD (see
		-- PlayerSpeed.server.lua). Off the field you're always at Roblox's
		-- flat default (16), no matter this upgrade's level.
		base = 4,        -- studs/second at level 0 (Roblox default is 16 -- this is a slow trudge)
		maxLevel = 6,
		top = 60,        -- studs/second at maxLevel -- PlayerSpeed.server.lua's own speed cap
		unit = " spd",
		decimal = true,  -- show one decimal place
		baseCost = 50,   -- Cash to go from level 0 -> 1
		growth = 3,      -- cost multiplies by this each level (exponential) -- only 6
		                 -- levels exist now, so this needs to climb faster than the
		                 -- old 1.5 did to still land somewhere meaningful by the top
	},

	Capacity = {
		name = "Batteries you can carry",
		base = 5,        -- battery SLOTS at level 0, regardless of size
		maxLevel = 6,
		top = 64,        -- battery SLOTS at maxLevel
		unit = "",
		baseCost = 50,
		growth = 3,
	},
}

-- Fill in `perLevel` for every def -- a straight line from `base` (level 0)
-- to `top` (level `maxLevel`), so nobody has to hand-calculate a fraction
-- like "59 batteries spread over 6 levels" and risk it not landing exactly
-- on `top`. See the header comment for why this beats a hand-picked number.
for _, d in Upgrades.defs do
	d.perLevel = (d.top - d.base) / d.maxLevel
end

-- The gameplay value this upgrade produces at a given level.
function Upgrades.effect(id, level)
	local d = Upgrades.defs[id]
	local value = d.base + level * d.perLevel

	if d.decimal then
		return value
	end

	-- Whole-number upgrades (Capacity) round to the nearest integer.
	-- perLevel above is rarely a round number itself (59/6 batteries, here)
	-- so without this, most levels would land on a fraction of a battery --
	-- meaningless to carry, and formatEffect's "%d" below would flat-out
	-- error on a non-whole number.
	return math.round(value)
end

-- The Cash price to buy the NEXT level (i.e. to go from `level` to `level + 1`).
-- Grows exponentially: baseCost, baseCost*growth, baseCost*growth^2, ...
-- (Doesn't itself stop at maxLevel -- Shop.server.lua is what refuses a
-- purchase once a player's already there.)
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

return Upgrades
