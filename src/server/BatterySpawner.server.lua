--[[
	BatterySpawner  --  Server Script, lives in ServerScriptService

	The SERVER half of the batteries:
	  1. clones one of the battery models from ServerStorage (random size)
	  2. places each clone UPRIGHT at a random point in a square area (it hovers)
	  3. tags it so the client's BatterySpin/BatteryGlow scripts will animate it
	  4. on a player touching a battery's Hitbox -- if they have room (Capacity
	     upgrade) -- adds that battery's mAh to their score and a slot to their count
	  5. if nobody collects it in time, or once it's collected, it's replaced

	Rarer batteries are worth more mAh AND vanish faster if left uncollected --
	see BASE_LIFETIME / LIFETIME_FALLOFF below -- so they reward rushing for them.

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

-- ============================ CONFIG ============================
-- Change these numbers to retune the game. Everything below reads from here.
local BATTERY_COUNT = 15                       -- how many batteries exist at once
local AREA_CENTER   = Vector3.new(-5, 0, -21)  -- middle of the spawn field (near the spawn pad)
local AREA_SIZE     = 120                      -- batteries spawn inside a 120 x 120 stud square
local BASE_HOVER    = 1.8                      -- how far a battery's BOTTOM floats above the baseplate
local RESPAWN_DELAY = 3                        -- seconds between a battery being COLLECTED and a new one appearing
local BATTERY_TAG   = "BatteryPickup"          -- CollectionService tag the client watches for

-- The battery models to clone, in order from COMMONEST to RAREST. Each has its
-- pivot at its own CENTRE. Every size counts as 1 SLOT when carried -- the sizes
-- differ in mAh and lifetime, not in how much room they take up.
local BATTERY_TEMPLATES = { "Battery_AAA", "Battery", "Battery_C", "Battery_D" }

-- Each size in the list spawns this many times less often than the one before it,
-- so the odds fall off exponentially. With 4 sizes and a falloff of 3 the mix is
-- roughly AAA 68% / AA 22% / C 7% / D 3%.
local RARITY_FALLOFF = 3

-- Battery capacity (mAh) also scales by the SAME falloff, so a battery is worth
-- as much power as it is rare: AAA = Upgrades.BASE_BATTERY_MAH, and each rarer
-- size is RARITY_FALLOFF times that (AAA 500 / AA 1500 / C 4500 / D 13500). This
-- is the SAME constant the data center's base power need is anchored to.

-- How long an uncollected battery sticks around before it vanishes and
-- reappears elsewhere. Rarer sizes live this many times LESS long, so a D
-- battery is a race against the clock, not a guaranteed pickup.
local BASE_LIFETIME    = 60   -- seconds, for AAA (the commonest / longest-lived)
local LIFETIME_FALLOFF = 2    -- AAA 60s / AA 30s / C 15s / D 7.5s
-- ==============================================================

-- Look each template up once. Record its height (to float sizes with their
-- bottoms lined up), its spawn weight (falloff ^ steps-from-the-rarest), its mAh
-- value (falloff ^ steps-from-the-commonest), its rarity rank (1 = commonest,
-- for the client's BatteryGlow to pick a glow tier), and its lifetime.
local templates = {}   -- { { model, height, weight, mah, rarity, lifetime }, ... }
local totalWeight = 0
for i, name in BATTERY_TEMPLATES do
	local model = ServerStorage:WaitForChild(name, 10)
	assert(model, "BatterySpawner: missing template '" .. name .. "' in ServerStorage")
	local _, size = model:GetBoundingBox()
	local weight = RARITY_FALLOFF ^ (#BATTERY_TEMPLATES - i)
	totalWeight += weight
	table.insert(templates, {
		model = model,
		height = size.Y,
		weight = weight,
		mah = math.floor(Upgrades.BASE_BATTERY_MAH * RARITY_FALLOFF ^ (i - 1)),
		rarity = i,
		lifetime = BASE_LIFETIME / LIFETIME_FALLOFF ^ (i - 1),
	})
end

-- Pick a template at random, biased by weight -- commoner sizes win more often.
local function pickTemplate()
	local roll = math.random() * totalWeight
	for _, entry in templates do
		roll -= entry.weight
		if roll <= 0 then
			return entry
		end
	end
	return templates[#templates]   -- float rounding safety net
end

-- Pick a random hover position inside the square, for a battery `height` tall.
local function randomCenterPosition(height)
	local half = AREA_SIZE / 2
	local x = AREA_CENTER.X + math.random(-half, half)
	local z = AREA_CENTER.Z + math.random(-half, half)
	return Vector3.new(x, BASE_HOVER + height / 2, z)
end

-- Create one battery and wire up what happens when it's collected or expires.
local function spawnBattery()
	local pick = pickTemplate()
	local battery = pick.model:Clone()

	local centerPos = randomCenterPosition(pick.height)
	battery:PivotTo(CFrame.new(centerPos))          -- upright; the client applies the lean + spin
	battery:SetAttribute("SpawnCenter", centerPos)  -- the client reads this to know the point to pivot around
	battery:SetAttribute("mAh", pick.mah)           -- this battery's capacity (for anything that inspects it)
	battery:SetAttribute("Rarity", pick.rarity)     -- 1 (AAA) .. 4 (D); the client uses this to pick a glow tier
	CollectionService:AddTag(battery, BATTERY_TAG)
	battery.Parent = workspace                      -- set parent LAST, so it replicates with attribute + tag already on it

	-- A clone made on the server is fully built right away, so .Hitbox is safe here.
	local hitbox = battery.Hitbox
	local collected = false   -- guard: both .Touched (many times per footstep) and
	                          -- the expiry timer can try to remove this battery

	-- Removes this battery (only once, however it happens) and queues its
	-- replacement `delay` seconds later.
	local function removeBattery(delay)
		if collected then
			return
		end
		collected = true
		battery:Destroy()
		task.delay(delay, spawnBattery)
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

		removeBattery(RESPAWN_DELAY)
	end)

	-- If nobody collects it before its lifetime is up, it vanishes and a fresh
	-- one appears elsewhere -- no extra delay, it already had its turn.
	task.delay(pick.lifetime, function()
		removeBattery(0)
	end)
end

-- Fill the field when the server starts.
for i = 1, BATTERY_COUNT do
	spawnBattery()
end
