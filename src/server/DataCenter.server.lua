--[[
	DataCenter  --  Server Script, lives in ServerScriptService

	The dump-off loop. Walk onto Workspace.DataCenter.Pad carrying batteries and
	they all get fed into the "AI data center": your Batteries count drops to 0,
	and the data center runs for a while, paying you Cash every second.

		run time added   = batteriesDumped * SECONDS_PER_BATTERY
		cash while running = CASH_PER_SECOND every second, until the time runs out
		so total cash     = batteriesDumped * SECONDS_PER_BATTERY * CASH_PER_SECOND

	Dumping again while it's still running just adds more seconds to the timer.
	Each player has their own independent run; the Pad is only the trigger.

	(Upgrades that change these numbers are a later step.)

	Note: the DataCenter model lives in the .rbxl place file, not in this repo.
--]]

local Players = game:GetService("Players")

-- ============================ CONFIG ============================
local SECONDS_PER_BATTERY = 2   -- run time each dumped battery buys
local CASH_PER_SECOND     = 5   -- cash paid per second while running
local PAYOUT_INTERVAL     = 1   -- seconds between payouts (keep at 1 for whole-second math)
local DUMP_DEBOUNCE       = 1   -- ignore repeat touches from the same player for this long
-- ==============================================================

local dataCenter = workspace:WaitForChild("DataCenter", 10)
assert(dataCenter, "DataCenter: no 'DataCenter' model found in Workspace (it lives in the place file)")
local pad = dataCenter:WaitForChild("Pad")

-- player -> seconds of run time left
local runs = {}
-- player -> os.clock() of their last dump (debounce)
local lastDump = {}

-- Tell THIS player's client how much run time they have left. The Pad is one
-- shared part, so its "ONLINE" glow is drawn per-client from this attribute
-- (see src/client/DataCenterDisplay.client.lua) -- if the server lit the Pad,
-- everyone would see it lit whenever anyone's run was active.
local function publish(player)
	player:SetAttribute("DataCenterSecondsLeft", runs[player] or 0)
end

local function getStat(player, name)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild(name)
end

-- Walk onto the pad -> dump whatever batteries you're carrying.
pad.Touched:Connect(function(hit)
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if not player then
		return
	end

	local now = os.clock()
	if now - (lastDump[player] or 0) < DUMP_DEBOUNCE then
		return
	end

	local batteries = getStat(player, "Batteries")
	if not batteries or batteries.Value <= 0 then
		return   -- nothing to dump
	end

	local dumped = batteries.Value
	batteries.Value = 0
	lastDump[player] = now

	runs[player] = (runs[player] or 0) + dumped * SECONDS_PER_BATTERY
	publish(player)

	print(string.format(
		"%s dumped %d batteries -> data center runs %d more seconds (now %d)",
		player.Name, dumped, dumped * SECONDS_PER_BATTERY, runs[player]
	))
end)

-- Clean up state when someone leaves.
Players.PlayerRemoving:Connect(function(player)
	runs[player] = nil
	lastDump[player] = nil
end)

-- The payout loop: once a second, pay every active run and count it down.
task.spawn(function()
	while true do
		task.wait(PAYOUT_INTERVAL)

		for player, secondsLeft in runs do
			local cash = getStat(player, "Cash")
			if cash then
				cash.Value += CASH_PER_SECOND * PAYOUT_INTERVAL
			end

			local remaining = secondsLeft - PAYOUT_INTERVAL
			if remaining > 0 then
				runs[player] = remaining
			else
				runs[player] = nil
				print(player.Name .. "'s data center powered down")
			end

			publish(player)   -- keep this player's client in sync each tick
		end
	end
end)

-- Make sure every player has the attribute from the start (0 = OFFLINE).
Players.PlayerAdded:Connect(publish)
for _, player in Players:GetPlayers() do
	publish(player)
end
