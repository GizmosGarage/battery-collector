--[[
	Fields  --  ModuleScript, lives in ReplicatedStorage (shared)

	The single source of truth for the FOUR battery fields: what each is
	named in Workspace, what MIX of battery sizes spawns on it, and how much
	LIFETIME Cash a player needs before they're allowed to collect there at
	all. BatterySpawner.server.lua reads `chances` to build each field's
	spawn pool and `unlockCash` to gate collection; PlayerSpeed.server.lua
	only needs `isOnAnyField` (any of the four counts as "the field" for the
	Speed upgrade's TRUE speed -- see Upgrades.lua).

	"Lifetime" Cash means total ever EARNED, not your current spendable
	balance -- it only ever goes up, even as you spend on upgrades and GPUs,
	so a field unlock (see FieldLockDisplay.client.lua) is truly PERMANENT,
	never something spending your way back down could take away.

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
--
-- `unlockCash` is the LIFETIME Cash required before a player can collect
-- anything there at all -- 0 (Green) means always open. Batteries still
-- SPAWN normally on a locked field (so you can see what you're working
-- toward through the sign -- see FieldLockDisplay.client.lua), you just
-- can't pick them up yet. Roughly scaled to what buying into that tier's
-- GPUs would already cost (see GPUs.lua) -- Yellow ~ a Basic GPU + slot 2,
-- Blue ~ an Advanced GPU + slot 3, Red ~ a Data Center GPU + slot 4 -- so
-- reaching a field lines up with being able to actually use what's there.
Fields.defs = {
	{ name = "Field_Green",  chances = { Battery_AAA = 100 }, count = 1, unlockCash = 0 },
	{ name = "Field_Yellow", chances = { Battery_AAA = 65, Battery = 35 }, count = 4, unlockCash = 2500 },
	{ name = "Field_Blue",   chances = { Battery_AAA = 20, Battery = 55, Battery_C = 25 }, count = 8, unlockCash = 25000 },
	{ name = "Field_Red",    chances = { Battery_AAA = 10, Battery = 20, Battery_C = 60, Battery_D = 10 }, count = 15, unlockCash = 250000 },
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

-- One field's whole def, by name -- lets BatterySpawner/FieldLockDisplay
-- look a field up by name instead of scanning Fields.defs themselves.
local defsByName = nil
function Fields.getDef(name)
	if not defsByName then
		defsByName = {}
		for _, def in Fields.defs do
			defsByName[def.name] = def
		end
	end
	return defsByName[name]
end

-- Has a player with this much LIFETIME Cash unlocked this field?
function Fields.isUnlockedFor(name, lifetimeCash)
	local def = Fields.getDef(name)
	return def ~= nil and lifetimeCash >= def.unlockCash
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
