--[[
	Shop  --  Server Script, lives in ServerScriptService

	Owns TWO kinds of purchase now, plus rearranging hardware you already own:
	  1. LEVEL upgrades (Speed, Capacity) -- one level per id in
	     Upgrades.defs, published as "<id>Level" attributes. Unchanged from
	     before the GPU system existed.
	  2. Data center SPACE (see GPUs.lua) -- how big the building is -- is
	     itself TWO independent purchases at the Data Center Shop now:
	       a. a RACK (GPUs.rackPrice) -- one more physical Server_Rack's
	          worth of equipment SLOTS. Capped by the current FLOOR tier.
	       b. a FLOOR upgrade (GPUs.floorTiers) -- room for MORE racks
	          (how many varies by tier -- see GPUs.floorTiers), without
	          buying those racks themselves.
	     `unlockedSlots` is always `racksOwned * GPUs.SLOTS_PER_RACK` --
	     every slot in an owned rack comes free with it; there's no
	     separate per-slot purchase.
	  3. GPU hardware (see GPUs.lua) -- a player has 4-256 EQUIPMENT SLOTS
	     (set by how many racks they own), plus unlimited STORAGE for
	     GPUs they own but aren't running. Slot 1 starts with a free
	     Starter GPU already installed. Every GPU (including a second
	     Starter) costs its own catalog price to BUY -- buying ALWAYS goes
	     straight to storage (never auto-installs); the player picks WHICH
	     physical Server_Rack a stored GPU fills by walking up to it
	     (RackShopUI.client.lua), one rack's worth of slots at a time
	     (GPUs.rackSlotRange) -- that's also where UNEQUIPPING happens now.
	     Moving a GPU between a slot and storage costs nothing either way;
	     it's just rearranging hardware you already own.

	Slot state publishes as "FloorTier" (index into GPUs.floorTiers),
	"RacksOwned" (how many racks are actually bought), "UnlockedSlots"
	(racksOwned * GPUs.SLOTS_PER_RACK), and "Slot<N>GPU" (that slot's
	GPU id, or "" if empty) attributes. Storage is a variable-length list,
	which an attribute can't hold directly -- it publishes as
	"GPUStorageJSON", a JSON-encoded array of GPU ids
	(HttpService:JSONEncode/Decode work locally; no network access or
	"Allow HTTP Requests" setting needed for these two). Together these let
	DataCenter.server.lua and the client read a player's whole rig --
	installed AND stored -- without this script sharing its internal
	tables with anyone.

	The client shows the shop UI (or a rack's panel) and clicks a button;
	that fires one of FIVE RemoteEvents to here. The SERVER decides
	whether any purchase or rearrangement is allowed -- never the client.

	Levels and the whole rig now PERSIST (see PlayerData.lua): a new player
	starts from the same defaults as before, but a returning one picks up
	exactly where they left off. Slots save as a plain array ("" = empty,
	padded/read out to GPUs.MAX_SLOTS long) and storage as a plain list of
	ids -- not the sparse `gpus` table this script uses live -- because
	DataStores handle a plain array far more predictably than a table with
	gaps in its numeric keys.
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

local buyRackEvent = Instance.new("RemoteEvent")
buyRackEvent.Name = "BuyServerRack"
buyRackEvent.Parent = ReplicatedStorage

local buyFloorEvent = Instance.new("RemoteEvent")
buyFloorEvent.Name = "BuyDataCenterFloor"
buyFloorEvent.Parent = ReplicatedStorage

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

-- player -> { floorTier = n, racksOwned = n, unlockedSlots = n,
--             gpus = { [slotIndex] = gpuId or nil },
--             storage = { gpuId, gpuId, ... } }
-- `floorTier` is an index into GPUs.floorTiers (how many racks there's ROOM
-- for); `racksOwned` is how many the player has actually bought (never
-- more than GPUs.maxRacksForTier(floorTier)); `unlockedSlots` is always
-- kept equal to `racksOwned * GPUs.SLOTS_PER_RACK`, never set independently
-- (see setupPlayer, buyRackEvent, and buyFloorEvent below). `storage` can
-- hold duplicates (two Basics owned but only one equipped) -- it's just a
-- bag of ids, order doesn't mean anything.
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
	player:SetAttribute("FloorTier", rig.floorTier)
	player:SetAttribute("RacksOwned", rig.racksOwned)
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
	-- since this player last played). Also clamp down to maxLevel, in case
	-- this save predates Upgrades.lua ever HAVING one -- Speed/Capacity used
	-- to be buyable forever, so an old save could easily sit well past 6.
	local lv = {}
	for id, def in Upgrades.defs do
		lv[id] = math.min(data.levels[id] or 0, def.maxLevel)
	end
	levels[player] = lv
	publishLevels(player)

	-- Rig: rebuild the live sparse `gpus` table from the saved slots
	-- array, skipping "" (empty) and any id the catalog no longer
	-- recognizes (defensive, in case a GPU is ever removed from GPUs.lua).
	-- `data.slots` might be shorter than GPUs.MAX_SLOTS (an older save, or
	-- one from before a space expansion) -- indexing past its length just
	-- reads nil in Lua, which the "" check below treats the same as empty.
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

	-- unlockedSlots is DERIVED from racksOwned, not read back from the save
	-- -- see the header comment.
	local floorTier, racksOwned = data.floorTier, data.racksOwned
	if not floorTier or not racksOwned then
		-- An older save, from before racks/floor were two separate
		-- purchases -- convert its `spaceTier` into an equivalent
		-- racksOwned/floorTier that keeps exactly the same slot count the
		-- player already had, so this upgrade never regresses anyone's
		-- progress. (`data.spaceTier` itself is left alone -- an unused
		-- leftover key, harmless once every save has floorTier/racksOwned.)
		local oldMaxSlots = ({ 4, 8, 16, 32 })[data.spaceTier or 1] or 4
		racksOwned = oldMaxSlots // GPUs.SLOTS_PER_RACK
		floorTier = #GPUs.floorTiers
		for i, tier in GPUs.floorTiers do
			if tier.maxRacks >= racksOwned then
				floorTier = i
				break
			end
		end
	end
	-- Clamp floorTier itself first -- a save from before a floor tier was
	-- ever REMOVED (e.g. the old "Column 3", 48-rack checkpoint that used
	-- to sit between "Column 2" and "Column 4") can hold an index past the
	-- end of the CURRENT GPUs.floorTiers, which would otherwise leave this
	-- player's FloorTier attribute pointing at nil and crash the first
	-- script that indexes it (ShopUI.client.lua's Data Center Shop panel).
	-- Falling back to the new largest tier costs a returning player
	-- nothing -- they already had the room such a save implies.
	floorTier = math.min(floorTier, #GPUs.floorTiers)
	-- Clamp racksOwned to what the floor tier actually allows (defensive,
	-- same spirit as the levels clamp above) in case the two ever disagree.
	racksOwned = math.min(racksOwned, GPUs.maxRacksForTier(floorTier) or racksOwned)
	rigs[player] = {
		floorTier = floorTier,
		racksOwned = racksOwned,
		unlockedSlots = racksOwned * GPUs.SLOTS_PER_RACK,
		gpus = gpus,
		storage = storage,
	}
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
		data.floorTier = rig.floorTier
		data.racksOwned = rig.racksOwned
		data.unlockedSlots = rig.unlockedSlots
		local slots = {}
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

-- The first EMPTY slot number within [rangeStart, rangeEnd] that's also
-- UNLOCKED, or nil if none qualify -- equipGPUEvent's range is one rack's
-- worth of slots (GPUs.rackSlotRange), so this only ever fills a slot in
-- the SPECIFIC rack the player walked up to, never a different one.
local function firstEmptySlotInRange(rig, rangeStart, rangeEnd)
	for i = rangeStart, math.min(rangeEnd, rig.unlockedSlots) do
		if not rig.gpus[i] then
			return i
		end
	end
	return nil
end

-- ---------- level upgrades (Speed, Capacity) ----------
-- A purchase request from a client. `id` is whatever the client sent -- distrust it.
buyEvent.OnServerEvent:Connect(function(player, id)
	local def = Upgrades.defs[id]
	if not def then
		return   -- not a real upgrade id
	end

	local lv = levels[player]
	if not lv then
		return
	end

	if lv[id] >= def.maxLevel then
		return   -- already at the top level -- nothing left to buy
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

-- ---------- data center: buy a server rack ----------
-- Buy the NEXT physical rack -- +GPUs.SLOTS_PER_RACK equipment slots.
-- Capped by the current FLOOR tier's room (see buyFloorEvent below for the
-- other half of expanding space).
buyRackEvent.OnServerEvent:Connect(function(player)
	local rig = rigs[player]
	if not rig then
		return
	end

	local nextRack = rig.racksOwned + 1
	local capacity = GPUs.maxRacksForTier(rig.floorTier)
	if not capacity or nextRack > capacity then
		return   -- no room left on this floor -- needs a floor upgrade first
	end

	local price = GPUs.rackPrice(nextRack)
	local cash = getCash(player)
	if not cash or cash.Value < price then
		return
	end

	cash.Value -= price
	rig.racksOwned = nextRack
	rig.unlockedSlots = rig.racksOwned * GPUs.SLOTS_PER_RACK
	publishRig(player)

	print(string.format("%s bought server rack #%d (paid %d Cash)", player.Name, nextRack, price))
end)

-- ---------- data center: upgrade the floor ----------
-- Buy room for a whole new ROW of racks (+3) -- doesn't buy the racks
-- themselves, just raises the ceiling buyRackEvent above can reach.
buyFloorEvent.OnServerEvent:Connect(function(player)
	local rig = rigs[player]
	if not rig then
		return
	end

	local nextTier = rig.floorTier + 1
	local tier = GPUs.floorTiers[nextTier]
	if not tier then
		return   -- already at the biggest floor there is
	end

	local cash = getCash(player)
	if not cash or cash.Value < tier.price then
		return
	end

	cash.Value -= tier.price
	rig.floorTier = nextTier
	publishRig(player)

	print(string.format("%s expanded the data center to %s (paid %d Cash)", player.Name, tier.name, tier.price))
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

	-- Always goes to storage now -- buying never auto-installs. Which
	-- physical rack (and which slot in it) a GPU ends up in is the
	-- player's own choice, made by walking up to that rack (see
	-- RackShopUI.client.lua and equipGPUEvent below), not a side effect of
	-- purchasing it.
	table.insert(rig.storage, gpu.id)
	publishRig(player)

	print(string.format("%s bought %s (paid %d Cash) -> storage", player.Name, gpu.name, gpu.price))
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

-- Move one GPU OUT of storage and into a SPECIFIC rack's first empty slot.
-- `rackIndex` is which physical Server_Rack the player walked up to (1,
-- 2, 3... left to right -- see RackShopUI.client.lua, which shows this
-- panel only while near one and sends its number); GPUs.rackSlotRange
-- turns that into the flat slot-number range this rack owns. Free, same
-- as unequipping -- this is the other half of a "swap" (unequip the old
-- one at the Data Center Shop, then walk over and equip the new one
-- here). `gpuId` identifies WHICH stored GPU by id, not by position --
-- duplicates are interchangeable, so it just removes the first matching one.
equipGPUEvent.OnServerEvent:Connect(function(player, gpuId, rackIndex)
	local rig = rigs[player]
	if not rig then
		return
	end
	if type(rackIndex) ~= "number" then
		return
	end
	rackIndex = math.floor(rackIndex)
	if rackIndex < 1 then
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

	local rangeStart, rangeEnd = GPUs.rackSlotRange(rackIndex)
	local emptySlot = firstEmptySlotInRange(rig, rangeStart, rangeEnd)
	if not emptySlot then
		return   -- this rack has no empty, unlocked slot right now
	end

	table.remove(rig.storage, storageIndex)
	rig.gpus[emptySlot] = gpuId
	publishRig(player)

	print(string.format("%s equipped %s from storage into slot %d (rack %d)", player.Name, gpuId, emptySlot, rackIndex))
end)
