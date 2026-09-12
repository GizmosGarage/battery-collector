--[[
	PlayerData  --  ModuleScript, lives in ServerScriptService (server-only --
	unlike src/shared/, nothing here is ever visible to the client)

	The single place that talks to Roblox's DataStoreService, so a player's
	progress survives leaving and rejoining. Everything else (PlayerSetup,
	Shop, DataCenter) still owns ITS OWN live state during play (leaderstats,
	upgrade levels, the GPU rig, the power reserve) -- this module's job is
	just getting that state INTO one saved table when it's time to save, and
	handing it back OUT when a player (re)joins.

	How the three systems plug in, without PlayerData needing to know
	anything about upgrades, GPUs, or Cash itself:

	  1. On PlayerAdded, each system calls `PlayerData.load(player)` to get
	     this player's save table (a fresh, default one for a new player, or
	     whatever was saved last time) -- then applies whatever fields are
	     ITS to apply (Shop reads .levels/.unlockedSlots/.slots/.storage;
	     DataCenter reads .reserve; PlayerSetup reads .cash).
	  2. Each system also calls `PlayerData.registerSaver(fn)` ONCE, at
	     script startup -- `fn(player, data)` is that system's chance to
	     write ITS current live values back into `data` right before a save
	     actually happens. (This is the same shape as a class implementing
	     one interface method -- every saver gets called the same way, and
	     PlayerData doesn't care what's inside any of them.)

	Saving itself happens on a timer, when a player leaves, and once more
	when the whole server shuts down -- NOT after every single change,
	which would run into DataStore's request-rate limits fast.

	NOT saved (by design, for now): Batteries/mAh currently CARRIED --
	an in-progress collecting trip resets each session, same as it always
	has. Offline earnings (whether the data center keeps draining/paying
	out while you're gone) is a separate decision for later -- right now,
	the reserve just picks up EXACTLY where it was, the instant you're
	back, nothing simulated for the time in between.
--]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local PlayerData = {}

-- ============================ CONFIG ============================
local STORE_NAME        = "PlayerSave_v1"   -- bump this (v2, v3, ...) if the save SHAPE ever changes incompatibly
local AUTO_SAVE_INTERVAL = 120              -- seconds between automatic saves for every player online
-- ==============================================================

local store = DataStoreService:GetDataStore(STORE_NAME)

-- player -> that player's save table (the SAME table the whole game reads
-- and writes through -- there's only ever one copy in memory per player).
local cache = {}

-- player -> true while a load for them is already in progress, so two
-- systems calling PlayerData.load at the same moment don't both fire a
-- separate DataStore request for the same player.
local loading = {}

-- Every function registered with PlayerData.registerSaver, called in order
-- whenever a save happens.
local savers = {}

-- Every function registered with PlayerData.onReleased, called (in order)
-- right after a leaving player's final save AND release -- see why this
-- matters, instead of each system just using its own Players.PlayerRemoving,
-- in the comment above that connection below.
local releaseListeners = {}

-- What a brand-new player starts with, or what a player falls back to if
-- their save fails to load (network hiccup, DataStore outage, etc.) --
-- better to start them fresh than to block them from playing at all.
local function defaultData()
	return {
		cash = 0,
		levels = {},                    -- upgrade id -> level (Shop.server.lua fills this in)
		unlockedSlots = 1,
		slots = { "Starter", "", "", "" },  -- ALWAYS 4 entries, "" = empty -- see Shop.server.lua
		storage = {},                    -- list of owned-but-unequipped GPU ids
		reserve = 0,                     -- banked power (mAh) at the Data Center
	}
end

local function keyFor(player)
	return "Player_" .. player.UserId
end

-- Load (or create) `player`'s save table, and return the ONE table every
-- system should read/write from now on. Safe to call from more than one
-- script's PlayerAdded handler -- the real DataStore request only ever
-- happens once per player; everyone else just waits for it.
function PlayerData.load(player)
	if cache[player] then
		return cache[player]
	end

	if loading[player] then
		-- Someone else already started loading this player -- wait for
		-- them to finish instead of asking the DataStore a second time.
		while loading[player] do
			task.wait()
		end
		return cache[player]
	end

	loading[player] = true

	local ok, saved = pcall(function()
		return store:GetAsync(keyFor(player))
	end)

	if ok and saved then
		cache[player] = saved
	else
		if not ok then
			warn(("PlayerData: couldn't load %s's save (%s) -- starting fresh"):format(player.Name, tostring(saved)))
		end
		cache[player] = defaultData()
	end

	loading[player] = nil
	return cache[player]
end

-- Register a function that contributes to every save from now on.
-- `fn(player, data)` should read whatever live state that system owns and
-- write it onto `data` -- it'll be called once per save, for every
-- currently-loaded player.
function PlayerData.registerSaver(fn)
	table.insert(savers, fn)
end

-- Run every registered saver against `player`'s cached table (bringing it
-- fully up to date with live state) and write the result to the DataStore.
function PlayerData.save(player)
	local data = cache[player]
	if not data then
		return   -- never loaded (e.g. left before setup finished) -- nothing to save
	end

	for _, saver in savers do
		saver(player, data)
	end

	local ok, err = pcall(function()
		store:SetAsync(keyFor(player), data)
	end)
	if not ok then
		warn(("PlayerData: couldn't save %s's progress (%s)"):format(player.Name, tostring(err)))
	end
end

-- Save every player currently loaded. Used by the auto-save timer and by
-- the server-shutdown handler below.
function PlayerData.saveAll()
	for player in cache do
		PlayerData.save(player)
	end
end

-- Forget a player's cached data (call AFTER their final save, once they've
-- actually left -- there's nothing left in memory to keep around for them).
function PlayerData.release(player)
	cache[player] = nil
	loading[player] = nil
end

-- Register a function to run right after a leaving player's final save and
-- release -- for a system's OWN cleanup of ITS per-player tables (Shop's
-- `levels`/`rigs`, DataCenter's `runs`, etc).
--
-- Why not just have each system add its own Players.PlayerRemoving
-- connection for this, the way the game did before saving existed? Because
-- Roblox fires every connection for one event in an unspecified order
-- relative to OTHER scripts, and if a system happened to clear its table
-- BEFORE this module's own PlayerRemoving handler got its turn to call
-- `save` (which reads that very table through a registered saver), the
-- player's last few moments would silently vanish from their save.
-- Funneling cleanup through here instead guarantees save-then-release-then
-- -cleanup happens in that exact order, every time, no matter how many
-- scripts are involved or what order they happened to load in.
function PlayerData.onReleased(fn)
	table.insert(releaseListeners, fn)
end

-- ---------- the lifecycle every player goes through ----------
-- Save (with every system's latest state), THEN drop them from memory,
-- THEN let every system clean up its own tables -- always in that exact
-- order (see PlayerData.onReleased above for why the order matters).
Players.PlayerRemoving:Connect(function(player)
	PlayerData.save(player)
	PlayerData.release(player)
	for _, fn in releaseListeners do
		fn(player)
	end
end)

-- A safety net against progress loss from crashes or unexpected shutdowns
-- between someone leaving -- saves everyone who's currently loaded, on a
-- timer, the whole time the server's up.
task.spawn(function()
	while true do
		task.wait(AUTO_SAVE_INTERVAL)
		PlayerData.saveAll()
	end
end)

-- The server shutting down (a deploy, a restart, Studio's Stop button) --
-- Roblox pauses shutdown briefly for this, so everyone gets one last save.
game:BindToClose(function()
	PlayerData.saveAll()
end)

return PlayerData
