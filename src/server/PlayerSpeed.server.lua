--[[
	PlayerSpeed  --  Server Script, lives in ServerScriptService

	Walk speed is now purely a SHOP UPGRADE (see Shop.server.lua / Upgrades.lua)
	-- it no longer depends on how much you're carrying. That's the tradeoff:
	Cash spent on Speed is Cash you didn't spend on Capacity, Seconds, or Cash/sec.

		WalkSpeed = Upgrades.effect("Speed", SpeedLevel), capped at MAX_WALKSPEED

	Driven off the "SpeedLevel" attribute Shop.server.lua publishes, so speed
	always matches your purchased level.
--]]

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))

-- ============================ CONFIG ============================
local MAX_WALKSPEED = 60   -- upper limit, so it stays controllable
-- ==============================================================

-- Make new characters spawn at the level-0 speed, instead of flashing normal
-- speed for a frame before this script catches them.
StarterPlayer.CharacterWalkSpeed = Upgrades.effect("Speed", 0)

local function speedForLevel(level)
	return math.min(Upgrades.effect("Speed", level), MAX_WALKSPEED)
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

	humanoid.WalkSpeed = speedForLevel(player:GetAttribute("SpeedLevel") or 0)
end

local function onPlayerAdded(player)
	-- Re-apply every time this player (re)spawns.
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
		applySpeed(player)
	end)

	-- React the instant Shop.server.lua bumps our Speed level.
	player:GetAttributeChangedSignal("SpeedLevel"):Connect(function()
		applySpeed(player)
	end)

	-- Cover a character that already exists when we get here.
	applySpeed(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
