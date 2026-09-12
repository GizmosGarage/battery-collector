--[[
	Upgrades  --  ModuleScript, lives in ReplicatedStorage (shared)

	The single source of truth for every LEVEL-based shop upgrade: what each
	level does, and what the next level costs. Both the server (Shop,
	PlayerSpeed, BatterySpawner) and the client (ShopUI) require this, so the
	numbers can never disagree.

	Levels are 0-based. Level 0 = the base value, no purchases made.

	Speed and Capacity make YOU better at collecting. Cash-per-second used to
	be a level here too (and dumping used to have its own Power Conversion
	level on top of it), but both are GPU hardware and a straight 1:1 dump
	now -- see GPUs.lua and Shop.server.lua's slot system -- so this module
	only covers the two upgrades that are still a simple "buy the next level."
--]]

local Upgrades = {}

-- The shop is THREE platforms -- Speed/Capacity make YOU better at
-- collecting; GPUs and equipment slots (see GPUs.lua) make the DATA CENTER
-- better at cashing out, split across their own two pads so neither panel
-- has to cram both a catalog and a slot list into one scroll. Each entry
-- lives on its own pad (see ShopUI.client.lua's SHOP_PAD_NAMES, in this
-- same order). `title` is what that pad's floating sign says.
-- `gpuCatalogSection`/`slotsSection` tell ShopUI to also build the GPU
-- catalog rows, or the slot-unlock + per-slot rows, on that platform --
-- this module doesn't need to know anything about GPUs itself, just that a
-- shop has room for one of those sections.
Upgrades.shops = {
	{ title = "PLAYER SHOP", ids = { "Speed", "Capacity" } },
	{ title = "GPU SHOP",    ids = {}, gpuCatalogSection = true },
	{ title = "SLOTS SHOP",  ids = {}, slotsSection = true },
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

return Upgrades
