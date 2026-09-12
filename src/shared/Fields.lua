--[[
	Fields  --  ModuleScript, lives in ReplicatedStorage (shared)

	The single source of truth for the FOUR battery fields: what each is
	named in Workspace, and which battery sizes are allowed to spawn on it.
	BatterySpawner.server.lua reads `templateNames` to build each field's
	spawn pool; PlayerSpeed.server.lua only needs `isOnAnyField` (any of the
	four counts as "the field" for the Speed upgrade's TRUE speed -- see
	Upgrades.lua).

	The Pads themselves (size, position, color) live in the .rbxl place
	file, not here -- this module only knows their NAMES, and reads their
	live Size/Position off Workspace, so resizing or moving a Pad in Studio
	needs no code change anywhere.
--]]

local Fields = {}

-- Commonest/smallest field first. `templateNames` is which battery MODEL
-- names (from ServerStorage) are allowed to spawn there -- always a run of
-- the commonest sizes, so reaching a bigger field is what unlocks the
-- rarer, more valuable ones. Field_Red allows everything -- it's the same
-- field the game started with, just recolored.
--
-- `count` is OPTIONAL: how many batteries that field holds at once. Leave
-- it out and BatterySpawner works one out itself from the field's own area
-- (the same density the original single field used); set it here to pin an
-- exact number instead -- Green and Red are left to the formula (which
-- happens to land on 1 and 15), Yellow and Blue are pinned because Ethan
-- wants those two busier than their tiny footprints would otherwise imply.
Fields.defs = {
	{ name = "Field_Green",  templateNames = { "Battery_AAA" } },
	{ name = "Field_Yellow", templateNames = { "Battery_AAA", "Battery" }, count = 4 },
	{ name = "Field_Blue",   templateNames = { "Battery_AAA", "Battery", "Battery_C" }, count = 8 },
	{ name = "Field_Red",    templateNames = { "Battery_AAA", "Battery", "Battery_C", "Battery_D" } },
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
