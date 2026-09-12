-- PlayerSetup
-- Runs on the SERVER at startup. Gives every player a "leaderstats" folder,
-- which Roblox automatically renders as the top-right scoreboard.

local Players = game:GetService("Players")

local PlayerData = require(script.Parent.PlayerData)

-- This function runs once for each player, the moment they join.
local function setupPlayer(player)
	-- Load (or create) this player's save -- Cash is the one leaderstat
	-- that persists; see the registerSaver call below.
	local data = PlayerData.load(player)

	-- A container. The name MUST be exactly "leaderstats" for Roblox to notice it.
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	-- An IntValue holds a whole number. Its Name is what shows as the column
	-- header, and its Value is what shows per player.

	-- Batteries = how many you're CARRYING right now (0 up to your Capacity
	-- upgrade), regardless of size. Resets to 0 when you dump -- and also
	-- each time you join, same as always: an in-progress collecting trip
	-- isn't part of what gets saved.
	local batteries = Instance.new("IntValue")
	batteries.Name = "Batteries"
	batteries.Value = 0
	batteries.Parent = leaderstats

	-- mAh = total battery capacity carried (each battery adds its own mAh; bigger,
	-- rarer batteries are worth more). Dumped at the data center for Cash.
	-- Also NOT saved, for the same reason as Batteries above.
	local mah = Instance.new("IntValue")
	mah.Name = "mAh"
	mah.Value = 0
	mah.Parent = leaderstats

	-- Cash: earned by dumping batteries at the AI data center (see DataCenter).
	-- This one DOES persist -- start at whatever the save says (0 for a
	-- brand-new player).
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = data.cash
	cash.Parent = leaderstats
end

-- Fire setupPlayer for everyone who joins from now on.
Players.PlayerAdded:Connect(setupPlayer)

-- Edge case: in a Studio playtest the server can start AFTER you've already
-- "joined", so PlayerAdded may have already fired. Catch anyone already here.
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

-- Contribute Cash to every save (PlayerData.lua calls this right before
-- writing to the DataStore).
PlayerData.registerSaver(function(player, data)
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash")
	if cash then
		data.cash = cash.Value
	end
end)
