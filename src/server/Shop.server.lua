--[[
	Shop  --  Server Script, lives in ServerScriptService

	Owns each player's two upgrade LEVELS and handles purchases.

	The client shows the shop UI and clicks "Buy"; that fires the BuyUpgrade
	RemoteEvent to here. The SERVER decides whether the purchase is allowed --
	never the client. We check the id is real, check the player can afford the
	cost (from the shared Upgrades module), take the Cash, and bump the level.

	Levels are published as attributes on the Player ("SecondsLevel", "CashLevel")
	so DataCenter and the client UI can read them.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))

-- The channel the client uses to ask for a purchase.
local buyEvent = Instance.new("RemoteEvent")
buyEvent.Name = "BuyUpgrade"
buyEvent.Parent = ReplicatedStorage

-- player -> { Seconds = <level>, Cash = <level> }
local levels = {}

local function publish(player)
	local lv = levels[player]
	if not lv then
		return
	end
	player:SetAttribute("SecondsLevel", lv.Seconds)
	player:SetAttribute("CashLevel", lv.Cash)
end

local function setupPlayer(player)
	levels[player] = { Seconds = 0, Cash = 0 }
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
	if id ~= "Seconds" and id ~= "Cash" then
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
