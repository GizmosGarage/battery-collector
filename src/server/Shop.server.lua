--[[
	Shop  --  Server Script, lives in ServerScriptService

	Owns TWO kinds of purchase now:
	  1. LEVEL upgrades (Speed, Capacity, Efficiency) -- one level per id in
	     Upgrades.defs, published as "<id>Level" attributes. Unchanged from
	     before the GPU system existed.
	  2. GPU hardware (see GPUs.lua) -- a player has 1-4 EQUIPMENT SLOTS.
	     Slot 1 is free and starts with a free Starter GPU already
	     installed; slots 2-4 cost Cash to unlock, and every GPU (including
	     a second Starter) costs its own catalog price to buy. Buying one
	     auto-installs it into the first empty unlocked slot -- there's no
	     swapping/storage yet (see GPUs.lua's header comment).

	Slot state publishes as "UnlockedSlots" (how many slots exist) and
	"Slot<N>GPU" (that slot's GPU id, or "" if empty) attributes, so
	DataCenter.server.lua and the client can read a player's whole rig
	without this script sharing its internal tables with anyone.

	The client shows the shop UI and clicks Buy; that fires one of three
	RemoteEvents to here. The SERVER decides whether any purchase is
	allowed -- never the client.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))
local GPUs = require(ReplicatedStorage:WaitForChild("GPUs"))

-- The channels the client uses to ask for a purchase.
local buyEvent = Instance.new("RemoteEvent")
buyEvent.Name = "BuyUpgrade"
buyEvent.Parent = ReplicatedStorage

local buySlotEvent = Instance.new("RemoteEvent")
buySlotEvent.Name = "BuyGPUSlot"
buySlotEvent.Parent = ReplicatedStorage

local buyGPUEvent = Instance.new("RemoteEvent")
buyGPUEvent.Name = "BuyGPU"
buyGPUEvent.Parent = ReplicatedStorage

-- player -> { [upgradeId] = level, ... } -- one entry per id in Upgrades.defs
local levels = {}

-- player -> { unlockedSlots = n, gpus = { [slotIndex] = gpuId or nil } }
local rigs = {}

local function publishLevels(player)
	local lv = levels[player]
	if not lv then
		return
	end
	for id, level in lv do
		player:SetAttribute(id .. "Level", level)
	end
end

local function publishRig(player)
	local rig = rigs[player]
	if not rig then
		return
	end
	player:SetAttribute("UnlockedSlots", rig.unlockedSlots)
	for i = 1, GPUs.MAX_SLOTS do
		player:SetAttribute("Slot" .. i .. "GPU", rig.gpus[i] or "")
	end
end

local function setupPlayer(player)
	local lv = {}
	for id in Upgrades.defs do
		lv[id] = 0
	end
	levels[player] = lv
	publishLevels(player)

	-- Slot 1 is free and comes with a free Starter GPU already installed --
	-- this is the ONLY GPU anyone gets without paying its catalog price.
	rigs[player] = { unlockedSlots = 1, gpus = { [1] = GPUs.STARTER_ID } }
	publishRig(player)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	levels[player] = nil
	rigs[player] = nil
end)

local function getCash(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Cash")
end

-- ---------- level upgrades (Speed, Capacity, Efficiency) ----------
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
	publishLevels(player)

	print(string.format("%s bought %s -> level %d (paid %d Cash)", player.Name, id, lv[id], cost))
end)

-- ---------- GPU equipment slots ----------
buySlotEvent.OnServerEvent:Connect(function(player)
	local rig = rigs[player]
	if not rig then
		return
	end

	local nextSlot = rig.unlockedSlots + 1
	if nextSlot > GPUs.MAX_SLOTS then
		return   -- already at the max
	end

	local price = GPUs.slotPrice(nextSlot)
	local cash = getCash(player)
	if not cash or cash.Value < price then
		return
	end

	cash.Value -= price
	rig.unlockedSlots = nextSlot
	publishRig(player)

	print(string.format("%s unlocked GPU slot %d (paid %d Cash)", player.Name, nextSlot, price))
end)

-- ---------- GPUs themselves ----------
-- `gpuId` is whatever the client sent -- distrust it, same as an upgrade id.
buyGPUEvent.OnServerEvent:Connect(function(player, gpuId)
	local gpu = GPUs.get(gpuId)
	if not gpu then
		return   -- not a real GPU id
	end

	local rig = rigs[player]
	if not rig then
		return
	end

	-- Find the first EMPTY unlocked slot -- a purchase auto-installs into
	-- it. No swapping/storage yet: every unlocked slot already full means
	-- the purchase is refused (unlock another slot first).
	local emptySlot
	for i = 1, rig.unlockedSlots do
		if not rig.gpus[i] then
			emptySlot = i
			break
		end
	end
	if not emptySlot then
		return
	end

	local cash = getCash(player)
	if not cash or cash.Value < gpu.price then
		return
	end

	cash.Value -= gpu.price
	rig.gpus[emptySlot] = gpu.id
	publishRig(player)

	print(string.format("%s bought %s into slot %d (paid %d Cash)", player.Name, gpu.name, emptySlot, gpu.price))
end)
