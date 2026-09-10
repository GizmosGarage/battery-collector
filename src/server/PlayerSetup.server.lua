-- PlayerSetup
-- Runs on the SERVER at startup. Gives every player a "leaderstats" folder,
-- which Roblox automatically renders as the top-right scoreboard.

local Players = game:GetService("Players")

-- This function runs once for each player, the moment they join.
local function setupPlayer(player)
	-- A container. The name MUST be exactly "leaderstats" for Roblox to notice it.
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	-- An IntValue holds a whole number. Its Name is what shows as the column
	-- header, and its Value (starting at 0) is what shows per player.
	local batteries = Instance.new("IntValue")
	batteries.Name = "Batteries"
	batteries.Value = 0
	batteries.Parent = leaderstats

	-- Cash: earned by dumping batteries at the AI data center (see DataCenter).
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = 0
	cash.Parent = leaderstats
end

-- Fire setupPlayer for everyone who joins from now on.
Players.PlayerAdded:Connect(setupPlayer)

-- Edge case: in a Studio playtest the server can start AFTER you've already
-- "joined", so PlayerAdded may have already fired. Catch anyone already here.
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end
