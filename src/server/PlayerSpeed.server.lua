--[[
	PlayerSpeed  --  Server Script, lives in ServerScriptService

	The player starts slow and speeds up with every battery collected.
	(Theme: the more power you've hoarded, the more capacity you have.)

		WalkSpeed = BASE_WALKSPEED + (batteries collected * SPEED_PER_BATTERY)
		           capped at MAX_WALKSPEED

	Driven off leaderstats.Batteries, which the server owns, so speed always
	matches the real score.
--]]

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

-- ============================ CONFIG ============================
local BASE_WALKSPEED    = 4     -- Roblox default is 16; this is a slow trudge
local SPEED_PER_BATTERY = 1.5   -- studs/second added per battery collected
local MAX_WALKSPEED     = 60    -- upper limit, so it stays controllable
-- ==============================================================

-- Make new characters spawn already slow, instead of flashing normal speed for
-- a frame before this script catches them.
StarterPlayer.CharacterWalkSpeed = BASE_WALKSPEED

local function speedForCount(count)
	return math.min(BASE_WALKSPEED + count * SPEED_PER_BATTERY, MAX_WALKSPEED)
end

-- Push the right WalkSpeed onto a player's current character, if they have one.
local function applySpeed(player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then
		return
	end

	local batteries = player:FindFirstChild("leaderstats")
		and player.leaderstats:FindFirstChild("Batteries")
	local count = (batteries and batteries.Value) or 0

	humanoid.WalkSpeed = speedForCount(count)
end

local function onPlayerAdded(player)
	-- Re-apply every time this player (re)spawns.
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
		applySpeed(player)
	end)

	-- Wait for PlayerSetup to have created the counter, then react to every change.
	local batteries = player:WaitForChild("leaderstats"):WaitForChild("Batteries")
	batteries.Changed:Connect(function()
		applySpeed(player)
	end)

	-- Cover a character that already exists when we get here.
	applySpeed(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
