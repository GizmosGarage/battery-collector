--[[
	DataCenter  --  Server Script, lives in ServerScriptService

	The dump-off loop. Walk onto Workspace.DataCenter.Pad carrying battery
	capacity and it all gets fed into the "AI data center" as a POWER RESERVE:
	your mAh drops to 0, and that much (times your Efficiency upgrade) becomes
	fuel in the tank.

	Every second the data center runs, it DRAWS power from that reserve --
	Upgrades.powerNeeded(CashLevel) mAh -- and pays out Cash:

		reserve added  = mAh dumped * Efficiency upgrade's multiplier
		power draw/sec = Upgrades.powerNeeded(CashLevel)   -- more GPUs, more draw
		cash/sec       = Upgrades.effect("Cash", CashLevel)

	Buying Cash ("adding a GPU") pays more but drains the reserve faster. Buying
	Efficiency makes every battery you dump deliver more reserve. Those two
	upgrades now directly pull against each other -- Cash is no longer a free
	upgrade to stack.

	If the reserve can't cover a full second's draw, the data center just idles
	-- whatever's left stays banked for your next dump; nothing is destroyed.

	Dumping again while it's still running just adds more reserve.
	Each player has their own independent run; the Pad is only the trigger.

	Note: the DataCenter model lives in the .rbxl place file, not in this repo.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))

-- ============================ CONFIG ============================
local PAYOUT_INTERVAL = 1   -- seconds between payouts (keep at 1 -- power draw is defined per second)
local DUMP_DEBOUNCE   = 1   -- ignore repeat touches from the same player for this long
-- Cash/sec, power draw (mAh/sec), and dump efficiency all come per-player from
-- the Upgrades module, scaled by that player's purchased upgrade levels.
-- ==============================================================

local dataCenter = workspace:WaitForChild("DataCenter", 10)
assert(dataCenter, "DataCenter: no 'DataCenter' model found in Workspace (it lives in the place file)")
local pad = dataCenter:WaitForChild("Pad")

-- player -> mAh of power reserve currently banked
local runs = {}
-- player -> os.clock() of their last dump (debounce)
local lastDump = {}

-- Tell THIS player's client roughly how many seconds their reserve will last at
-- their CURRENT power draw. The Pad is one shared part, so its "ONLINE" glow is
-- drawn per-client from this attribute (see DataCenterDisplay.client.lua) -- if
-- the server lit the Pad, everyone would see it lit whenever anyone's ran.
local function publish(player)
	local reserve = runs[player] or 0
	local powerDraw = Upgrades.powerNeeded(player:GetAttribute("CashLevel") or 0)
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
			local powerDraw = Upgrades.powerNeeded(player:GetAttribute("CashLevel") or 0)

			if reserve >= powerDraw then
				local cash = getStat(player, "Cash")
				if cash then
					cash.Value += Upgrades.effect("Cash", player:GetAttribute("CashLevel") or 0)
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
