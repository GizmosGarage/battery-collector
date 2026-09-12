--[[
	DataCenter  --  Server Script, lives in ServerScriptService

	The dump-off loop. Walk onto Workspace.DataCenter.Pad carrying battery
	capacity and it all gets fed into the "AI data center" as a POWER RESERVE:
	your mAh drops to 0, and that much (times your Efficiency upgrade) becomes
	fuel in the tank.

	Every second the data center runs, it DRAWS power from that reserve --
	the COMBINED power draw of every GPU installed in your equipment slots
	(see GPUs.lua and Shop.server.lua) -- and pays out the COMBINED Cash/sec
	of those same GPUs:

		reserve added  = mAh dumped * Efficiency upgrade's multiplier
		power draw/sec = sum of installed GPUs' powerDraw
		cash/sec       = sum of installed GPUs' cashPerSec

	This is all-or-nothing per second, same as before the GPU system: if the
	reserve can cover the WHOLE rig's draw, every installed GPU pays out and
	the reserve drains by the full total; if it can't, the whole rig idles
	this tick -- nothing partially runs. (A future pass could let individual
	GPUs "brown out" independently; this first pass keeps the simpler
	single-reserve-vs-single-draw model the game already had.)

	Buying a bigger/second GPU pays more but drains the reserve faster.
	Buying Efficiency makes every battery you dump deliver more reserve.
	Those two pull against each other -- more GPUs is not a free upgrade.

	Dumping again while it's still running just adds more reserve.
	Each player has their own independent run; the Pad is only the trigger.

	Note: the DataCenter model lives in the .rbxl place file, not in this repo.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))
local GPUs = require(ReplicatedStorage:WaitForChild("GPUs"))

-- ============================ CONFIG ============================
local PAYOUT_INTERVAL = 1   -- seconds between payouts (keep at 1 -- power draw is defined per second)
local DUMP_DEBOUNCE   = 1   -- ignore repeat touches from the same player for this long
-- Cash/sec and power draw come from whichever GPUs a player has installed
-- (see rigTotals below); dump efficiency still comes from the Upgrades module.
-- ==============================================================

local dataCenter = workspace:WaitForChild("DataCenter", 10)
assert(dataCenter, "DataCenter: no 'DataCenter' model found in Workspace (it lives in the place file)")
local pad = dataCenter:WaitForChild("Pad")

-- player -> mAh of power reserve currently banked
local runs = {}
-- player -> os.clock() of their last dump (debounce)
local lastDump = {}

-- Sum up a player's whole rig, straight off the attributes Shop.server.lua
-- publishes ("UnlockedSlots", "Slot<N>GPU") -- this script never needs to
-- know about purchases or slots, just the totals they add up to.
local function rigTotals(player)
	local unlocked = player:GetAttribute("UnlockedSlots") or 0
	local cashPerSec, powerDraw = 0, 0
	for i = 1, unlocked do
		local id = player:GetAttribute("Slot" .. i .. "GPU")
		local gpu = id ~= "" and GPUs.get(id)
		if gpu then
			cashPerSec += gpu.cashPerSec
			powerDraw += gpu.powerDraw
		end
	end
	return cashPerSec, powerDraw
end

-- Tell THIS player's client roughly how many seconds their reserve will last at
-- their CURRENT power draw. The Pad is one shared part, so its "ONLINE" glow is
-- drawn per-client from this attribute (see DataCenterDisplay.client.lua) -- if
-- the server lit the Pad, everyone would see it lit whenever anyone's ran.
local function publish(player)
	local reserve = runs[player] or 0
	local _, powerDraw = rigTotals(player)
	local secondsLeft = (powerDraw > 0) and math.floor(reserve / powerDraw) or 0
	player:SetAttribute("DataCenterSecondsLeft", secondsLeft)
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

	-- Efficiency upgrade: how much usable reserve each dumped mAh actually delivers.
	local efficiency = Upgrades.effect("Efficiency", player:GetAttribute("EfficiencyLevel") or 0)
	local addedReserve = math.floor(dumped * efficiency)

	runs[player] = (runs[player] or 0) + addedReserve
	publish(player)

	print(string.format(
		"%s dumped %d mAh (x%.2f efficiency -> %d reserve) -- data center now holds %d mAh",
		player.Name, dumped, efficiency, addedReserve, runs[player]
	))
end)

-- Clean up state when someone leaves.
Players.PlayerRemoving:Connect(function(player)
	runs[player] = nil
	lastDump[player] = nil
end)

-- The payout loop: once a second, every player with any banked reserve tries to
-- draw a second's worth of power. Enough reserve -> pay Cash, drain the reserve.
-- Not enough -> idle this tick; the reserve stays banked, untouched, for later.
task.spawn(function()
	while true do
		task.wait(PAYOUT_INTERVAL)

		for player, reserve in runs do
			local cashPerSec, powerDraw = rigTotals(player)

			if reserve >= powerDraw then
				local cash = getStat(player, "Cash")
				if cash then
					cash.Value += cashPerSec
				end
				runs[player] = reserve - powerDraw
			end

			publish(player)   -- keep this player's client in sync every tick
		end
	end
end)

-- Make sure every player has the attribute from the start (0 = OFFLINE).
Players.PlayerAdded:Connect(publish)
for _, player in Players:GetPlayers() do
	publish(player)
end
