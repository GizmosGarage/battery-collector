--[[
	DataCenterDisplay  --  LocalScript
	Location: StarterPlayer > StarterPlayerScripts

	Draws the data-centre Pad for THIS player only. The Pad is one shared part in
	the world, but each player should see it glowing "ONLINE" only while THEIR own
	dump is still paying out -- not whenever anyone's is.

	The server publishes each player's remaining run time as an attribute on the
	Player ("DataCenterSecondsLeft", set by DataCenter.server.lua). We read our
	own, then set the Pad's colour/material and the sign text locally. Local
	property changes to a shared part only affect our own view.

	The sign also shows how much power (mAh/sec) THIS player's data center needs
	to run at their current Cash upgrade level -- more Cash levels bought (more
	GPU units added) means a bigger draw. That number comes straight from the
	shared Upgrades module, so it always matches what the shop shows.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))

local LocalPlayer = Players.LocalPlayer

local PAD_COLOR_OFF = Color3.fromRGB(40, 40, 45)
local PAD_COLOR_ON  = Color3.fromRGB(60, 230, 140)

local dataCenter = workspace:WaitForChild("DataCenter")
local pad = dataCenter:WaitForChild("Pad")

-- The sign is optional -- degrade gracefully if it's missing.
local sign = dataCenter:WaitForChild("Sign", 5)
local billboard = sign and sign:WaitForChild("Billboard", 5)
local statusLabel = billboard and billboard:WaitForChild("Status", 5)
local powerLabel = billboard and billboard:WaitForChild("PowerDraw", 5)

local function render()
	local secondsLeft = LocalPlayer:GetAttribute("DataCenterSecondsLeft") or 0
	local online = secondsLeft > 0

	pad.Color = online and PAD_COLOR_ON or PAD_COLOR_OFF
	pad.Material = online and Enum.Material.Neon or Enum.Material.SmoothPlastic

	if statusLabel then
		statusLabel.Text = online and string.format("ONLINE  %ds", secondsLeft) or "OFFLINE"
	end

	if powerLabel then
		local draw = Upgrades.powerNeeded(LocalPlayer:GetAttribute("CashLevel") or 0)
		powerLabel.Text = string.format("Needs %d mAh/s to run", draw)
	end
end

LocalPlayer:GetAttributeChangedSignal("DataCenterSecondsLeft"):Connect(render)
LocalPlayer:GetAttributeChangedSignal("CashLevel"):Connect(render)   -- power draw changes when Cash is upgraded
render()
