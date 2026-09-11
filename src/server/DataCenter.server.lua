--[[
	DataCenter  --  Server Script, lives in ServerScriptService

	The dump-off loop. Walk onto Workspace.DataCenter.Pad carrying battery
	capacity and it all gets fed into the "AI data center": your mAh drops to 0,
	and the data center runs for a while, paying you Cash every second.

		run time added    = (mAh dumped / 1000) * secondsPer1000Mah   (Seconds upgrade)
		cash while running = cashPerSecond every second                (Cash upgrade)

	Dumping again while it's still running just adds more seconds to the timer.
	Each player has their own independent run; the Pad is only the trigger.

	Note: the DataCenter model lives in the .rbxl place file, not in this repo.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))

-- ============================ CONFIG ============================
local PAYOUT_INTERVAL = 1      -- seconds between payouts (keep at 1 for whole-second math)
local DUMP_DEBOUNCE   = 1      -- ignore repeat touches from the same player for this long
local MAH_PER_RUNTIME = 1000   -- how much dumped mAh buys one "unit" of the Seconds upgrade's run time
-- The per-second cash and the run time per unit come per-player from the Upgrades
-- module, scaled by that player's purchased upgrade levels.
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

	local mah = getStat(player, "mAh")
	if not mah or mah.Value <= 0 then
		return   -- nothing to dump
	end

	local dumped = mah.Value
	mah.Value = 0
	lastDump[player] = now

	-- Dumping empties your whole inventory, not just its mAh -- free up your
	-- carried-battery slots too, so you can go collect again.
	local carried = getStat(player, "Batteries")
	if carried then
		carried.Value = 0
	end

	-- Run time per 1000 mAh for THIS player (their Seconds upgrade level).
	local secondsPerUnit = Upgrades.effect("Seconds", player:GetAttribute("SecondsLevel") or 0)
	local addedSeconds = math.floor((dumped / MAH_PER_RUNTIME) * secondsPerUnit)

	runs[player] = (runs[player] or 0) + addedSeconds
	publish(player)

	print(string.format(
		"%s dumped %d mAh -> data center runs %d more seconds (now %d)",
		player.Name, dumped, addedSeconds, runs[player]
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
				-- Cash/second for THIS player (their Cash upgrade level).
				local cashPerSecond = Upgrades.effect("Cash", player:GetAttribute("CashLevel") or 0)
				cash.Value += cashPerSecond * PAYOUT_INTERVAL
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
