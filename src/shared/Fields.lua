--[[
	Fields  --  ModuleScript, lives in ReplicatedStorage (shared)

	The single source of truth for the FOUR battery fields: what each is
	named in Workspace, and what MIX of battery sizes spawns on it.
	BatterySpawner.server.lua reads `chances` to build each field's spawn
	pool; PlayerSpeed.server.lua only needs `isOnAnyField` (any of the four
	counts as "the field" for the Speed upgrade's TRUE speed -- see
	Upgrades.lua).

	The Pads themselves (size, position, color) live in the .rbxl place
	file, not here -- this module only knows their NAMES, and reads their
	live Size/Position off Workspace, so resizing or moving a Pad in Studio
	needs no code change anywhere.
--]]

local Fields = {}

-- Commonest/smallest field first. `chances` is which battery MODEL names
-- (from ServerStorage) can spawn there, and how heavily each is weighted
-- against the others ON THIS FIELD -- the numbers only matter relative to
-- each other (BatterySpawner sums them and rolls against the total), so
-- they read naturally as "out of 100." A size missing from a field's
-- `chances` can never spawn there at all.
--
-- Each field is built to raise what counts as a NORMAL pickup: AAA is all
-- there is on Green; AA becomes the routine find on Blue; C becomes routine
-- on Red, with D as the rare, exciting exception (10%, a sixth as often as
-- C on the same field) rather than the everyday battery. A given size's
-- mAh/lifetime (see BATTERY_TEMPLATES below) never change field to field --
-- only how OFTEN it turns up does.
--
-- `count` is how many batteries that field holds at once -- change any
-- number here to retune that field, nothing else needs touching. It's
-- OPTIONAL, though: leave it off a field and BatterySpawner works one out
-- itself from that field's own area instead (the same density the original
-- single field used -- 960 sq studs/battery -- which is where Green's 1 and
-- Red's 15 originally came from, now written down explicitly below).
Fields.defs = {
	{ name = "Field_Green",  chances = { Battery_AAA = 100 }, count = 1 },
	{ name = "Field_Yellow", chances = { Battery_AAA = 65, Battery = 35 }, count = 4 },
	{ name = "Field_Blue",   chances = { Battery_AAA = 20, Battery = 55, Battery_C = 25 }, count = 8 },
	{ name = "Field_Red",    chances = { Battery_AAA = 10, Battery = 20, Battery_C = 60, Battery_D = 10 }, count = 15 },
}

-- Resolve every field's Pad instance once (WaitForChild blocks until the
-- place file has streamed them in), cached so later calls are instant.
local pads = nil
local function getPads()
	if not pads then
		pads = {}
		for _, def in Fields.defs do
			pads[def.name] = workspace:WaitForChild(def.name, 10):WaitForChild("Pad", 10)
		end
	end
	return pads
end

-- The live Pad instance for one field, by its Fields.defs name.
function Fields.getPad(name)
	return getPads()[name]
end

-- Is `position` (a world point) over ANY of the four fields? A 2-D
-- bounding-box test against each Pad's actual Size/Position in turn.
function Fields.isOnAnyField(position)
	for _, def in Fields.defs do
		local pad = getPads()[def.name]
		local half = pad.Size / 2
		local min, max = pad.Position - half, pad.Position + half
		if position.X >= min.X and position.X <= max.X
			and position.Z >= min.Z and position.Z <= max.Z then
			return true
		end
	end
	return false
end

return Fields
