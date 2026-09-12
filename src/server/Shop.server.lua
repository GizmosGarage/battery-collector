--[[
	Shop  --  Server Script, lives in ServerScriptService

	Owns TWO kinds of purchase now:
	  1. LEVEL upgrades (Speed, Capacity) -- one level per id in
	     Upgrades.defs, published as "<id>Level" attributes. Unchanged from
	     before the GPU system existed.
	  2. GPU hardware (see GPUs.lua) -- a player has 1-4 EQUIPMENT SLOTS,
	     plus unlimited STORAGE for GPUs they own but aren't running. Slot 1
	     is free and starts with a free Starter GPU already installed;
	     slots 2-4 cost Cash to unlock. Every GPU (including a second
	     Starter) costs its own catalog price to BUY -- buying auto-installs
	     it into the first empty unlocked slot, or straight into storage if
	     every slot is already full (buying never fails just because your
	     rig happens to be full). Moving a GPU between a slot and storage
	     -- EQUIPPING or UNEQUIPPING -- costs nothing; it's just
	     rearranging hardware you already own.

	Slot state publishes as "UnlockedSlots" (how many slots exist) and
	"Slot<N>GPU" (that slot's GPU id, or "" if empty) attributes, same as
	before. Storage is a variable-length list, which an attribute can't
	hold directly -- it publishes as "GPUStorageJSON", a JSON-encoded array
	of GPU ids (HttpService:JSONEncode/Decode work locally; no network
	access or "Allow HTTP Requests" setting needed for these two). Together
	these let DataCenter.server.lua and the client read a player's whole
	rig -- installed AND stored -- without this script sharing its
	internal tables with anyone.

	The client shows the shop UI and clicks a button; that fires one of
	FOUR RemoteEvents to here. The SERVER decides whether any purchase or
	rearrangement is allowed -- never the client.

	Levels and the whole rig now PERSIST (see PlayerData.lua): a new player
	starts from the same defaults as before, but a returning one picks up
	exactly where they left off. Slots save as a 4-entry array ("" = empty)
	and storage as a plain list of ids -- not the sparse `gpus` table this
	script uses live -- because DataStores handle a plain array far more
	predictably than a table with gaps in its numeric keys.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))
local GPUs = require(ReplicatedStorage:WaitForChild("GPUs"))
local PlayerData = require(script.Parent.PlayerData)

-- The channels the client uses to ask for a purchase or rearrangement.
local buyEvent = Instance.new("RemoteEvent")
buyEvent.Name = "BuyUpgrade"
buyEvent.Parent = ReplicatedStorage

local buySlotEvent = Instance.new("RemoteEvent")
buySlotEvent.Name = "BuyGPUSlot"
buySlotEvent.Parent = ReplicatedStorage

local buyGPUEvent = Instance.new("RemoteEvent")
buyGPUEvent.Name = "BuyGPU"
buyGPUEvent.Parent = ReplicatedStorage

local equipGPUEvent = Instance.new("RemoteEvent")
equipGPUEvent.Name = "EquipGPU"
equipGPUEvent.Parent = ReplicatedStorage

local unequipGPUEvent = Instance.new("RemoteEvent")
unequipGPUEvent.Name = "UnequipGPU"
unequipGPUEvent.Parent = ReplicatedStorage

-- player -> { [upgradeId] = level, ... } -- one entry per id in Upgrades.defs
local levels = {}

-- player -> { unlockedSlots = n, gpus = { [slotIndex] = gpuId or nil },
--             storage = { gpuId, gpuId, ... } }
-- `storage` can hold duplicates (two Basics owned but only one equipped) --
-- it's just a bag of ids, order doesn't mean anything.
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
	player:SetAttribute("GPUStorageJSON", HttpService:JSONEncode(rig.storage))
end

local function setupPlayer(player)
	local data = PlayerData.load(player)   -- a fresh player's save (all defaults) or a returning one's

	-- Levels: start every upgrade at its SAVED level, or 0 for one that
	-- doesn't exist yet in an older save (e.g. a brand-new upgrade added
	-- since this player last played).
	local lv = {}
	for id in Upgrades.defs do
		lv[id] = data.levels[id] or 0
	end
	levels[player] = lv
	publishLevels(player)

	-- Rig: rebuild the live sparse `gpus` table from the saved 4-entry
	-- array, skipping "" (empty) and any id the catalog no longer
	-- recognizes (defensive, in case a GPU is ever removed from GPUs.lua).
	local gpus = {}
	for i = 1, GPUs.MAX_SLOTS do
		local id = data.slots[i]
		if id and id ~= "" and GPUs.get(id) then
			gpus[i] = id
		end
	end

	local storage = {}
	for _, id in data.storage do
		if GPUs.get(id) then
			table.insert(storage, id)
		end
	end

	rigs[player] = { unlockedSlots = data.unlockedSlots or 1, gpus = gpus, storage = storage }
	publishRig(player)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

-- Runs AFTER this player's final save (see PlayerData.onReleased for why
-- that order matters) -- just forgetting our own tables now, nothing left
-- to write anywhere.
PlayerData.onReleased(function(player)
	levels[player] = nil
	rigs[player] = nil
end)

-- Contribute levels + the whole rig to every save (PlayerData.lua calls
-- this right before writing to the DataStore).
PlayerData.registerSaver(function(player, data)
	local lv = levels[player]
	if lv then
		data.levels = table.clone(lv)
	end

	local rig = rigs[player]
	if rig then
		data.unlockedSlots = rig.unlockedSlots
		local slots = { "", "", "", "" }
		for i = 1, GPUs.MAX_SLOTS do
			slots[i] = rig.gpus[i] or ""
		end
		data.slots = slots
		data.storage = table.clone(rig.storage)
	end
end)

local function getCash(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Cash")
end

-- The first EMPTY slot number among a rig's UNLOCKED slots, or nil if
-- they're all full. Shared by buying (auto-install) and equipping.
local function firstEmptySlot(rig)
	for i = 1, rig.unlockedSlots do
		if not rig.gpus[i] then
			return i
		end
	end
	return nil
end

-- ---------- level upgrades (Speed, Capacity) ----------
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

	local cash = getCash(player)
	if not cash or cash.Value < gpu.price then
		return
	end

	cash.Value -= gpu.price

	-- Auto-install into the first empty slot if there is one; otherwise it
	-- goes straight to storage. Buying always succeeds once it's paid for
	-- -- a full rig just means the new card waits in storage until
	-- something's unequipped or another slot's unlocked.
	local emptySlot = firstEmptySlot(rig)
	if emptySlot then
		rig.gpus[emptySlot] = gpu.id
	else
		table.insert(rig.storage, gpu.id)
	end
	publishRig(player)

	print(string.format(
		"%s bought %s (paid %d Cash) -> %s",
		player.Name, gpu.name, gpu.price, emptySlot and ("slot " .. emptySlot) or "storage"
	))
end)

-- Move one GPU OUT of a slot and into storage. Free -- you already own it,
-- this just idles it.
unequipGPUEvent.OnServerEvent:Connect(function(player, slotNumber)
	local rig = rigs[player]
	if not rig then
		return
	end
	if type(slotNumber) ~= "number" then
		return
	end
	slotNumber = math.floor(slotNumber)
	if slotNumber < 1 or slotNumber > rig.unlockedSlots then
		return
	end

	local gpuId = rig.gpus[slotNumber]
	if not gpuId then
		return   -- already empty, nothing to unequip
	end

	rig.gpus[slotNumber] = nil
	table.insert(rig.storage, gpuId)
	publishRig(player)

	print(string.format("%s unequipped %s from slot %d", player.Name, gpuId, slotNumber))
end)

-- Move one GPU OUT of storage and into the first empty slot. Free, same as
-- unequipping -- this is the other half of a "swap" (unequip the old one,
-- then equip the new one). `gpuId` identifies WHICH stored GPU by id, not
-- by position -- duplicates are interchangeable, so it just removes the
-- first matching one.
equipGPUEvent.OnServerEvent:Connect(function(player, gpuId)
	local rig = rigs[player]
	if not rig then
		return
	end

	local storageIndex
	for i, id in rig.storage do
		if id == gpuId then
			storageIndex = i
			break
		end
	end
	if not storageIndex then
		return   -- don't own a spare of this in storage
	end

	local emptySlot = firstEmptySlot(rig)
	if not emptySlot then
		return   -- no room -- unequip something first
	end

	table.remove(rig.storage, storageIndex)
	rig.gpus[emptySlot] = gpuId
	publishRig(player)

	print(string.format("%s equipped %s from storage into slot %d", player.Name, gpuId, emptySlot))
end)
