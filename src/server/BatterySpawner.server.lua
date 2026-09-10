--[[
	BatterySpawner  --  Server Script, lives in ServerScriptService

	The SERVER half of the batteries:
	  1. clones one of the battery models from ServerStorage (random size)
	  2. places each clone UPRIGHT at a random point in a square area (it hovers)
	  3. tags it so the client's BatterySpin LocalScript will lean + spin it
	  4. on a player touching a battery's Hitbox, adds 1 to their score
	  5. a few seconds after a battery is collected, spawns a fresh one elsewhere

	The lean and spin are PURELY VISUAL and now live in the client LocalScript
	(StarterPlayer > StarterPlayerScripts > BatterySpin), so no movement data is
	sent over the network. The server's battery -- and its Hitbox -- stays upright
	and still, which is what collection is measured against.
--]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

-- ============================ CONFIG ============================
-- Change these numbers to retune the game. Everything below reads from here.
local BATTERY_COUNT = 15                       -- how many batteries exist at once
local AREA_CENTER   = Vector3.new(-5, 0, -21)  -- middle of the spawn field (near the spawn pad)
local AREA_SIZE     = 120                      -- batteries spawn inside a 120 x 120 stud square
local BASE_HOVER    = 1.8                      -- how far a battery's BOTTOM floats above the baseplate
local RESPAWN_DELAY = 3                        -- seconds between a battery being collected and a new one appearing
local BATTERY_TAG   = "BatteryPickup"          -- CollectionService tag the client watches for

-- The battery models to clone, in order from COMMONEST to RAREST. Each has its
-- pivot at its own CENTRE. Every size counts as 1 when collected -- the sizes are
-- purely visual variety.
local BATTERY_TEMPLATES = { "Battery_AAA", "Battery", "Battery_C", "Battery_D" }

-- Each size in the list spawns this many times less often than the one before it,
-- so the odds fall off exponentially. With 4 sizes and a falloff of 3 the mix is
-- roughly AAA 68% / AA 22% / C 7% / D 3%.
local RARITY_FALLOFF = 3
-- ==============================================================

-- Look each template up once. Record its height (to float sizes with their
-- bottoms lined up) and its spawn weight (falloff ^ steps-from-the-rarest).
local templates = {}   -- { { model = Model, height = number, weight = number }, ... }
local totalWeight = 0
for i, name in BATTERY_TEMPLATES do
	local model = ServerStorage:WaitForChild(name, 10)
	assert(model, "BatterySpawner: missing template '" .. name .. "' in ServerStorage")
	local _, size = model:GetBoundingBox()
	local weight = RARITY_FALLOFF ^ (#BATTERY_TEMPLATES - i)
	totalWeight += weight
	table.insert(templates, { model = model, height = size.Y, weight = weight })
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

-- Create one battery and wire up what happens when it's collected.
local function spawnBattery()
	local pick = pickTemplate()
	local battery = pick.model:Clone()

	local centerPos = randomCenterPosition(pick.height)
	battery:PivotTo(CFrame.new(centerPos))          -- upright; the client applies the lean + spin
	battery:SetAttribute("SpawnCenter", centerPos)  -- the client reads this to know the point to pivot around
	CollectionService:AddTag(battery, BATTERY_TAG)
	battery.Parent = workspace                      -- set parent LAST, so it replicates with attribute + tag already on it

	-- A clone made on the server is fully built right away, so .Hitbox is safe here.
	local hitbox = battery.Hitbox
	local collected = false                -- guard: .Touched fires many times per footstep

	hitbox.Touched:Connect(function(hit)
		if collected then
			return
		end

		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then
			return
		end

		collected = true

		local leaderstats = player:FindFirstChild("leaderstats")
		local batteries = leaderstats and leaderstats:FindFirstChild("Batteries")
		if batteries then
			batteries.Value += 1
		end

		battery:Destroy()

		-- Queue a replacement to appear later, without pausing this script.
		task.delay(RESPAWN_DELAY, spawnBattery)
	end)
end

-- Fill the field when the server starts.
for i = 1, BATTERY_COUNT do
	spawnBattery()
end
