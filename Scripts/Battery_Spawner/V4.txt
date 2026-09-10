--[[
	BatterySpawner  --  Server Script, lives in ServerScriptService

	The SERVER half of the batteries:
	  1. clones a template model from ServerStorage
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

-- The model we copy. It lives in ServerStorage, so it never shows up in the
-- world on its own and never gets sent to players. Its pivot has been set to
-- the model's CENTRE, so PivotTo() rotates it around the middle.
local batteryTemplate = ServerStorage:WaitForChild("Battery", 10)
assert(batteryTemplate, "BatterySpawner: no 'Battery' template found in ServerStorage")

-- ============================ CONFIG ============================
-- Change these numbers to retune the game. Everything below reads from here.
local BATTERY_COUNT = 15                       -- how many batteries exist at once
local AREA_CENTER   = Vector3.new(-5, 0, -21)  -- middle of the spawn field (near the spawn pad)
local AREA_SIZE     = 120                      -- batteries spawn inside a 120 x 120 stud square
local CENTER_HEIGHT = 3                        -- height of a battery's CENTRE above the baseplate (so it hovers, clear of the floor when leaning)
local RESPAWN_DELAY = 3                        -- seconds between a battery being collected and a new one appearing
local BATTERY_TAG   = "BatteryPickup"          -- CollectionService tag the client watches for
-- ==============================================================

-- Pick a random hover position inside the square.
local function randomCenterPosition()
	local half = AREA_SIZE / 2
	local x = AREA_CENTER.X + math.random(-half, half)
	local z = AREA_CENTER.Z + math.random(-half, half)
	return Vector3.new(x, CENTER_HEIGHT, z)
end

-- Create one battery and wire up what happens when it's collected.
local function spawnBattery()
	local battery = batteryTemplate:Clone()

	local centerPos = randomCenterPosition()
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
