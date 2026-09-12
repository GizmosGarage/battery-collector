--[[
	BatterySpawner  --  Server Script, lives in ServerScriptService

	The SERVER half of the batteries. There are now FOUR fields (see
	Fields.lua) -- differently sized, differently colored raised platforms,
	each allowing a different mix of battery sizes:

		Field_Green   (smallest)  -- AAA only
		Field_Yellow               -- AAA, AA
		Field_Blue                -- AAA, AA, C
		Field_Red     (biggest)   -- AAA, AA, C, D

	Working up to a bigger field is what unlocks the rarer, more valuable
	sizes. Field_Red is exactly the field this game started with -- same
	size, same odds -- just recolored; the other three are smaller slices
	of the same idea.

	Each field's `count` (Fields.lua) is now a CAP, not a fixed number it's
	always at. How many batteries a field actually holds drifts randomly
	between 1 and that cap: every SPAWN_CHECK_INTERVAL seconds, a field
	that's under its cap rolls SPAWN_CHANCE odds of spawning one more. A
	field never OVERFLOWS its cap, but it doesn't snap straight back to full
	the instant something's collected either -- see startFieldLoop below.

	For each field, this script:
	  1. clones one of ITS allowed battery models from ServerStorage
	  2. places each clone UPRIGHT at a random point inside THAT field's own
	     square (inset from its Pad, so nothing spawns off the edge) -- it hovers
	  3. tags it so the client's BatterySpin/BatteryGlow scripts will animate it
	  4. on a player touching a battery's Hitbox -- if they have room (Capacity
	     upgrade) -- adds that battery's mAh to their score and a slot to their count
	  5. once it's collected, or if nobody collects it in time, it's removed --
	     the field's own refill loop (not this battery) decides when a
	     replacement eventually appears

	Rarer batteries are worth more mAh AND vanish faster if left uncollected --
	see BASE_LIFETIME / LIFETIME_FALLOFF below -- so they reward rushing for
	them. A battery's rarity/mAh/lifetime never change based on which field
	it's on -- only WHICH sizes can appear there does.

	The lean and spin are PURELY VISUAL and live in client LocalScripts
	(StarterPlayer > StarterPlayerScripts), so no movement data is sent over the
	network. The server's battery -- and its Hitbox -- stays upright and still,
	which is what collection is measured against.
--]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))
local Fields = require(ReplicatedStorage:WaitForChild("Fields"))

-- ============================ CONFIG ============================
local BASE_HOVER  = 1.8    -- how far a battery's BOTTOM floats above whichever field it's on
local BATTERY_TAG = "BatteryPickup"   -- CollectionService tag the client watches for

-- How a field's battery population refills over time. Every
-- SPAWN_CHECK_INTERVAL seconds, EACH field that's below its own cap
-- (Fields.lua's `count`) rolls SPAWN_CHANCE odds of spawning one more
-- battery. This randomness is what makes `count` a MAXIMUM a field can
-- hold rather than a fixed number it's always pinned at -- on average, a
-- slot takes SPAWN_CHECK_INTERVAL / SPAWN_CHANCE seconds to refill, but
-- exactly when varies every time.
local SPAWN_CHECK_INTERVAL = 2     -- seconds between refill rolls
local SPAWN_CHANCE         = 0.5   -- odds, per roll, of actually spawning (if under cap)

-- Batteries spawn inside a square INSET from each field's own Pad, so
-- nothing ever spawns at (or past) the edge. 0.8 = the spawn square is 80%
-- of the Pad's width/depth -- a 10% margin on every side.
local SPAWN_MARGIN_RATIO = 0.8

-- How many square studs of field each battery gets, on average -- the SAME
-- density the original single field used (120x120 studs / 15 batteries =
-- 960). Only used as a FALLBACK, for a field Fields.lua doesn't give an
-- explicit `count` to.
local BATTERIES_PER_SQUARE_STUD = 960

-- The battery models to clone, in order from COMMONEST to RAREST. Each has
-- its pivot at its own CENTRE. Every size counts as 1 SLOT when carried --
-- the sizes differ in mAh and lifetime, not in how much room they take up.
local BATTERY_TEMPLATES = { "Battery_AAA", "Battery", "Battery_C", "Battery_D" }

-- Each size in this list spawns this many times less often than the one
-- before it (among whatever sizes a given field allows), so the odds fall
-- off exponentially -- see the per-field renormalizing in buildField below.
local RARITY_FALLOFF = 3

-- Battery capacity (mAh) also scales by the SAME falloff, so a battery is
-- worth as much power as it is rare: AAA = Upgrades.BASE_BATTERY_MAH, and
-- each rarer size is RARITY_FALLOFF times that (AAA 500 / AA 1500 / C 4500
-- / D 13500). This is the SAME constant the data center's power need is
-- anchored to, and it never changes based on which field a battery is on.

-- How long an uncollected battery sticks around before it vanishes.
-- Rarer sizes live this many times LESS long, so a D battery is a race
-- against the clock, not a guaranteed pickup.
local BASE_LIFETIME    = 60   -- seconds, for AAA (the commonest / longest-lived)
local LIFETIME_FALLOFF = 2    -- AAA 60s / AA 30s / C 15s / D 7.5s
-- ==============================================================

-- Look each template up once, keyed by name. weight/mah/rarity are GLOBAL --
-- the same falloff^steps-from-rarest/commonest numbers no matter which
-- field a battery spawns on, so a AAA is exactly as common (relative to
-- whatever else that field allows) and worth exactly as much everywhere it
-- appears.
local templates = {}   -- name -> { model, height, weight, mah, rarity, lifetime }
for i, name in BATTERY_TEMPLATES do
	local model = ServerStorage:WaitForChild(name, 10)
	assert(model, "BatterySpawner: missing template '" .. name .. "' in ServerStorage")
	local _, size = model:GetBoundingBox()
	templates[name] = {
		model = model,
		height = size.Y,
		weight = RARITY_FALLOFF ^ (#BATTERY_TEMPLATES - i),
		mah = math.floor(Upgrades.BASE_BATTERY_MAH * RARITY_FALLOFF ^ (i - 1)),
		rarity = i,
		lifetime = BASE_LIFETIME / LIFETIME_FALLOFF ^ (i - 1),
	}
end

-- Turn one Fields.defs entry into a ready-to-spawn field: resolves its Pad,
-- works out its own spawn square from the Pad's ACTUAL size (so resizing a
-- Pad in Studio needs no code change here), and narrows `templates` down to
-- just the sizes this field allows -- re-summing their weight so picking is
-- still correctly weighted among only THOSE sizes. `liveCount` tracks how
-- many of this field's batteries currently exist, for startFieldLoop below.
local function buildField(def)
	local pad = Fields.getPad(def.name)

	local allowed, totalWeight = {}, 0
	for _, name in def.templateNames do
		local entry = templates[name]
		table.insert(allowed, entry)
		totalWeight += entry.weight
	end

	local areaSize = pad.Size.X * SPAWN_MARGIN_RATIO
	assert(
		areaSize <= pad.Size.X and areaSize <= pad.Size.Z,
		"BatterySpawner: spawn area bigger than " .. pad:GetFullName() .. " -- batteries would spawn off the platform"
	)

	-- Fields.lua can pin an exact cap (def.count); otherwise derive one
	-- from this field's own area, same density the original field used.
	local count = def.count or math.max(1, math.floor(areaSize ^ 2 / BATTERIES_PER_SQUARE_STUD + 0.5))

	return {
		name = def.name,
		center = pad.Position,
		fieldTop = pad.Position.Y + pad.Size.Y / 2,
		areaSize = areaSize,
		templates = allowed,
		totalWeight = totalWeight,
		count = count,       -- the CAP -- this field never holds more than this many at once
		liveCount = 0,        -- how many of this field's batteries exist RIGHT NOW
	}
end

local fields = {}
for _, def in Fields.defs do
	table.insert(fields, buildField(def))
end

-- Pick a template at random from ONE field's allowed list, biased by weight
-- -- commoner sizes (among that field's own allowed sizes) win more often.
local function pickTemplate(field)
	local roll = math.random() * field.totalWeight
	for _, entry in field.templates do
		roll -= entry.weight
		if roll <= 0 then
			return entry
		end
	end
	return field.templates[#field.templates]   -- float rounding safety net
end

-- Pick a random hover position inside `field`'s square, for a battery
-- `height` tall. The Y is measured from that field's OWN top surface, not
-- from Y = 0, so batteries hover just above whichever Pad they're on no
-- matter where that Pad sits in the world.
local function randomCenterPosition(field, height)
	local half = field.areaSize / 2
	local x = field.center.X + math.random(-half, half)
	local z = field.center.Z + math.random(-half, half)
	return Vector3.new(x, field.fieldTop + BASE_HOVER + height / 2, z)
end

-- Create one battery on `field` and wire up what happens when it's
-- collected or expires. Unlike before, removal does NOT queue its own
-- replacement -- that field's startFieldLoop is what decides if/when a new
-- one shows up, which is what lets the population sit below the cap.
local function spawnBattery(field)
	local pick = pickTemplate(field)
	local battery = pick.model:Clone()

	local centerPos = randomCenterPosition(field, pick.height)
	battery:PivotTo(CFrame.new(centerPos))          -- upright; the client applies the lean + spin
	battery:SetAttribute("SpawnCenter", centerPos)  -- the client reads this to know the point to pivot around
	battery:SetAttribute("mAh", pick.mah)           -- this battery's capacity (for anything that inspects it)
	battery:SetAttribute("Rarity", pick.rarity)     -- 1 (AAA) .. 4 (D); the client uses this to pick a glow tier
	CollectionService:AddTag(battery, BATTERY_TAG)
	battery.Parent = workspace                      -- set parent LAST, so it replicates with attribute + tag already on it
	field.liveCount += 1

	-- A clone made on the server is fully built right away, so .Hitbox is safe here.
	local hitbox = battery.Hitbox
	local collected = false   -- guard: both .Touched (many times per footstep) and
	                          -- the expiry timer can try to remove this battery

	-- Removes this battery (only once, however it happens) and frees up its
	-- slot -- the field's own loop decides when/if that slot gets refilled.
	local function removeBattery()
		if collected then
			return
		end
		collected = true
		battery:Destroy()
		field.liveCount -= 1
	end

	hitbox.Touched:Connect(function(hit)
		if collected then
			return
		end

		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then
			return
		end

		local leaderstats = player:FindFirstChild("leaderstats")
		local carried = leaderstats and leaderstats:FindFirstChild("Batteries")
		local mah = leaderstats and leaderstats:FindFirstChild("mAh")
		if not carried or not mah then
			return
		end

		-- Respect the player's Capacity upgrade -- full is full, no exceptions.
		local maxCarry = Upgrades.effect("Capacity", player:GetAttribute("CapacityLevel") or 0)
		if carried.Value >= maxCarry then
			return   -- can't carry any more; go dump first
		end

		carried.Value += 1
		mah.Value += pick.mah

		removeBattery()
	end)

	-- If nobody collects it before its lifetime is up, it vanishes.
	task.delay(pick.lifetime, removeBattery)
end

-- Keep `field` topped up ONLY probabilistically: every SPAWN_CHECK_INTERVAL
-- seconds, if it's under its cap, roll SPAWN_CHANCE odds of adding one more.
-- This is the loop that makes `field.count` a ceiling instead of a target
-- that's always immediately re-hit -- most checks either find the field
-- already full (nothing to do) or fail the roll (nothing happens this time).
local function startFieldLoop(field)
	task.spawn(function()
		while true do
			task.wait(SPAWN_CHECK_INTERVAL)
			if field.liveCount < field.count and math.random() < SPAWN_CHANCE then
				spawnBattery(field)
			end
		end
	end)
end

-- Give each field a random HEAD START -- somewhere between 1 and its cap,
-- inclusive -- instead of always snapping straight to the max on server
-- boot, then hand it off to its own loop to grow or drain from there.
for _, field in fields do
	local startCount = math.random(1, field.count)
	for _ = 1, startCount do
		spawnBattery(field)
	end
	startFieldLoop(field)
end
