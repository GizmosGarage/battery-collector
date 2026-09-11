--[[
	Shop  --  Server Script, lives in ServerScriptService

	Owns each player's upgrade LEVELS (one per id in Upgrades.defs) and handles
	purchases.

	The client shows the shop UI and clicks "Buy"; that fires the BuyUpgrade
	RemoteEvent to here. The SERVER decides whether the purchase is allowed --
	never the client. We check the id is real, check the player can afford the
	cost (from the shared Upgrades module), take the Cash, and bump the level.

	Levels are published as attributes on the Player ("SpeedLevel", "CapacityLevel",
	"SecondsLevel", "CashLevel") so DataCenter, PlayerSpeed, BatterySpawner, and the
	client UI can all read them. Reading Upgrades.defs here (instead of hardcoding
	the upgrade names) means adding a new upgrade only ever touches Upgrades.lua.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))

-- The channel the client uses to ask for a purchase.
local buyEvent = Instance.new("RemoteEvent")
buyEvent.Name = "BuyUpgrade"
buyEvent.Parent = ReplicatedStorage

-- player -> { [upgradeId] = level, ... } -- one entry per id in Upgrades.defs
local levels = {}

local function publish(player)
	local lv = levels[player]
	if not lv then
		return
	end
	for id, level in lv do
		player:SetAttribute(id .. "Level", level)
	end
end

local function setupPlayer(player)
	local lv = {}
	for id in Upgrades.defs do
		lv[id] = 0
	end
	levels[player] = lv
	publish(player)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	levels[player] = nil
end)

local function getCash(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Cash")
end

-- A purchase request from a client. `id` is whatever the client sent -- distrust it.
buyEvent.OnServerEvent:Connect(function(player, id)
	if not Upgrades.defs[id] then
		return   -- not a real upgrade id
	end

	local lv = levels[player]
	if not lv then
		return
	end

	local cost = Upgrades.cost(id, lv[id])
	local cash = getCash(player)
	if not cash or cash.Value < cost then
		return   -- can't afford it
	end

	cash.Value -= cost
	lv[id] += 1
	publish(player)

	print(string.format("%s bought %s -> level %d (paid %d Cash)", player.Name, id, lv[id], cost))
end)
