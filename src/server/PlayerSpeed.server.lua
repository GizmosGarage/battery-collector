--[[
	PlayerSpeed  --  Server Script, lives in ServerScriptService

	Two different speeds now, not one:

	  * NORMAL speed -- flat, constant, plain Roblox default (16 studs/sec).
	    Applies everywhere EXCEPT the four fields. The Speed upgrade does nothing
	    here -- walking to the Data Center or the Shop always feels the same,
	    no matter how much you've spent.
	  * TRUE speed -- your Speed upgrade actually applies here:
	        WalkSpeed = Upgrades.effect("Speed", SpeedLevel), capped at MAX_WALKSPEED
	    Applies ONLY while standing on one of the four fields (see
	    Fields.lua) -- the fields are what the Speed upgrade is FOR. Level 0
	    true speed is still the same slow trudge it always was (see
	    Upgrades.lua). Which field you're on doesn't matter -- ALL four give
	    you your true speed; only which battery SIZES you find differ.

	A loop checks every player's position against Fields.isOnAnyField (the
	same per-field bounding-box test BatterySpawner uses to keep batteries
	on their own Pad) a few times a second, and only touches
	Humanoid.WalkSpeed when which zone they're in -- or their SpeedLevel --
	actually changes.
--]]

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))
local Fields = require(ReplicatedStorage:WaitForChild("Fields"))

-- ============================ CONFIG ============================
local MAX_WALKSPEED    = 60   -- upper limit on TRUE speed, so it stays controllable
local NORMAL_WALKSPEED = 16   -- Roblox's own default WalkSpeed -- flat, never upgraded
local CHECK_INTERVAL   = 0.2  -- seconds between on/off-field checks (WalkSpeed doesn't need every physics frame)
-- ==============================================================

-- Characters spawn off every field (see Workspace.SpawnLocation), so start
-- them at NORMAL speed, not a frame of TRUE speed before this script catches them.
StarterPlayer.CharacterWalkSpeed = NORMAL_WALKSPEED

local function trueSpeedForLevel(level)
	return math.min(Upgrades.effect("Speed", level), MAX_WALKSPEED)
end

-- player -> the WalkSpeed we last actually set, so applySpeed only writes to
-- the Humanoid (which replicates to every client watching it) when the
-- number genuinely needs to change.
local appliedSpeed = {}

-- Work out which speed this player SHOULD have right now, and push it if
-- that's different from what they've currently got.
local function applySpeed(player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		return
	end

	local target = Fields.isOnAnyField(rootPart.Position)
		and trueSpeedForLevel(player:GetAttribute("SpeedLevel") or 0)
		or NORMAL_WALKSPEED

	if appliedSpeed[player] ~= target then
		humanoid.WalkSpeed = target
		appliedSpeed[player] = target
	end
end

local function onPlayerAdded(player)
	-- Re-apply every time this player (re)spawns.
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
		appliedSpeed[player] = nil   -- forget the old character's speed so the new one gets set fresh
		applySpeed(player)
	end)

	-- React the instant Shop.server.lua bumps our Speed level -- applySpeed
	-- itself decides whether that matters right now (only if we're on the field).
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

Players.PlayerRemoving:Connect(function(player)
	appliedSpeed[player] = nil
end)

-- The on/off-field check itself: cheap position test, run a few times a
-- second for every player rather than on every physics frame.
task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		for _, player in Players:GetPlayers() do
			applySpeed(player)
		end
	end
end)
