--[[
	StatusPanel  --  LocalScript
	Location: StarterPlayer > StarterPlayerScripts

	An ALWAYS-ON HUD panel, pinned to the top-left corner the whole time
	you're playing -- unlike the shop panels (ShopUI.client.lua), which only
	appear while you're standing on their own pad, or the Data Center's own
	Pad/sign (DataCenterDisplay.client.lua), which only show what's
	happening AT the data center. This one is meant to answer, at a glance,
	while you're out collecting: "how full am I, is my rig actually earning,
	how long until it stalls, and what am I working toward?"

	It sits top-left, below Roblox's own top inset bar (every ScreenGui is
	automatically pushed below that bar unless IgnoreGuiInset is set, which
	this one never does), so it never covers the leaderstats scoreboard
	(top-right) or overlaps the shop panels / Data Center sign (all centered
	on screen). Mobile's on-screen joystick and jump button live in the
	bottom corners, so a compact top-left box stays clear of those too.

	Every number here is read off attributes and leaderstats the SERVER
	already publishes -- this script never invents or recomputes gameplay
	values, only formats them:

		1. Battery bag fullness  -- leaderstats.Batteries, plus
		                            Upgrades.effect("Capacity", ...) (the
		                            SAME formula BatterySpawner.server.lua
		                            checks against when it lets you pick a
		                            battery up)
		2. Actual Cash/sec       -- GPUs.rigTotals(...) (shared with
		                            DataCenter.server.lua's own payout math),
		                            zeroed out unless the rig is actually
		                            paying out RIGHT NOW
		3. Remaining power time  -- LocalPlayer's "DataCenterSecondsLeft"
		                            attribute, published by
		                            DataCenter.server.lua every payout tick
		4. Next field milestone  -- Fields.defs + leaderstats.LifetimeCash

	The server stays the authority on all of it -- DataCenter.server.lua
	decides whether the rig is actually running and how much reserve is
	left, Shop.server.lua decides what's equipped, Fields.lua/PlayerSetup
	decide lifetime earnings. This script only DISPLAYS those numbers, same
	trust boundary as every other client script in this game.

	Nothing here runs per-frame: every line only repaints when the
	leaderstat or attribute behind it actually changes. The running
	countdown updates once a second because DataCenter.server.lua's own
	payout loop touches "DataCenterSecondsLeft" every PAYOUT_INTERVAL
	seconds for every player with a banked reserve -- not because this
	script polls anything on a timer.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))
local GPUs = require(ReplicatedStorage:WaitForChild("GPUs"))
local Fields = require(ReplicatedStorage:WaitForChild("Fields"))

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ============================ CONFIG ============================
local COLOR_BG        = Color3.fromRGB(24, 26, 32)
local COLOR_TEXT      = Color3.fromRGB(235, 237, 242)
local COLOR_TEXT_DIM  = Color3.fromRGB(160, 164, 174)
local COLOR_ONLINE    = Color3.fromRGB(60, 230, 140)   -- matches DataCenterDisplay's "ONLINE" pad color
local COLOR_BAR_BG    = Color3.fromRGB(40, 43, 52)
local COLOR_BAR_FILL  = Color3.fromRGB(90, 170, 235)

local PANEL_WIDTH = 230
local PADDING     = 12
local ROW_GAP     = 6
-- ==============================================================

-- ---------- building the panel (once; ResetOnSpawn keeps it alive across respawns) ----------
local screen = Instance.new("ScreenGui")
screen.Name = "StatusPanelUI"
screen.ResetOnSpawn = false   -- built once, never rebuilt on respawn -- see header
screen.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 0)
panel.Position = UDim2.fromOffset(PADDING, PADDING)
panel.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y   -- grows/shrinks with however many lines are visible
panel.BackgroundColor3 = COLOR_BG
panel.BackgroundTransparency = 0.12          -- a HUD stays put the whole time, so let a little of the world show through
panel.BorderSizePixel = 0
panel.Parent = screen
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

local uiPadding = Instance.new("UIPadding", panel)
uiPadding.PaddingTop = UDim.new(0, PADDING)
uiPadding.PaddingBottom = UDim.new(0, PADDING)
uiPadding.PaddingLeft = UDim.new(0, PADDING)
uiPadding.PaddingRight = UDim.new(0, PADDING)

local listLayout = Instance.new("UIListLayout", panel)
listLayout.Padding = UDim.new(0, ROW_GAP)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- A plain text row. `lines` is how many lines of text it should have room
-- for (1 or 2) -- everything here wraps instead of a fixed single line, so a
-- long field name or big number never gets clipped.
local function makeLabel(order, textSize, lines, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, textSize * lines + (lines - 1) * 2)
	label.Font = font or Enum.Font.GothamMedium
	label.TextSize = textSize
	label.TextColor3 = COLOR_TEXT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Text = ""
	label.LayoutOrder = order
	label.Parent = panel
	return label
end

local titleLabel = makeLabel(1, 16, 1, Enum.Font.GothamBold)
titleLabel.Text = "STATUS"

local loadingLabel = makeLabel(2, 13, 2)
loadingLabel.Text = "Loading player data..."
loadingLabel.TextColor3 = COLOR_TEXT_DIM

local bagLabel = makeLabel(3, 14, 1)
local earningLabel = makeLabel(4, 13, 2)
local powerLabel = makeLabel(5, 13, 1)
local milestoneLabel = makeLabel(6, 13, 2)

-- The field-milestone progress bar: a thin background track with a filled
-- bar on top, scaled to how far lifetime Cash is toward the next threshold.
local barBg = Instance.new("Frame")
barBg.Size = UDim2.new(1, 0, 0, 8)
barBg.BackgroundColor3 = COLOR_BAR_BG
barBg.BorderSizePixel = 0
barBg.LayoutOrder = 7
barBg.Parent = panel
Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 4)

local barFill = Instance.new("Frame")
barFill.AnchorPoint = Vector2.new(0, 0)
barFill.Position = UDim2.fromScale(0, 0)
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = COLOR_BAR_FILL
barFill.BorderSizePixel = 0
barFill.Parent = barBg
Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 4)

-- Rows that stay hidden until real player data has actually arrived (see
-- isDataReady below) -- the bar is included so it never flashes a 0%/full
-- bar built from fabricated-missing values before the real ones land.
local contentRows = { bagLabel, earningLabel, powerLabel, milestoneLabel, barBg }
for _, row in contentRows do
	row.Visible = false
end

-- ---------- formatting helpers ----------

-- Seconds -> "Xm Ys", or "Xh Ym" once it's an hour or more -- per-the-spec
-- formatting for the remaining-power-time line.
local function formatDuration(totalSeconds)
	totalSeconds = math.max(0, math.floor(totalSeconds))
	if totalSeconds >= 3600 then
		local hours = math.floor(totalSeconds / 3600)
		local minutes = math.floor((totalSeconds % 3600) / 60)
		return string.format("%dh %dm", hours, minutes)
	end
	local minutes = math.floor(totalSeconds / 60)
	local seconds = totalSeconds % 60
	return string.format("%dm %ds", minutes, seconds)
end

-- "Field_Yellow" -> "Yellow", for a short, readable milestone name.
local function fieldDisplayName(fieldName)
	return (fieldName:gsub("^Field_", ""))
end

-- Read this player's whole rig totals off the SAME attributes
-- Shop.server.lua publishes, through the shared GPUs.rigTotals helper
-- (also used by DataCenter.server.lua and DataCenterDisplay.client.lua) --
-- so this panel's Cash/sec and power draw can never disagree with either.
local function ownRigTotals()
	local unlocked = LocalPlayer:GetAttribute("UnlockedSlots") or 0
	return GPUs.rigTotals(unlocked, function(i)
		return LocalPlayer:GetAttribute("Slot" .. i .. "GPU")
	end)
end

-- ---------- rendering ----------
local ready = false

local function render()
	if not ready then
		return
	end

	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	if not leaderstats then
		return   -- mid-respawn hiccup; the next Changed/attribute signal will call render() again
	end

	-- 1. Battery bag fullness -- current carry vs. the SAME Capacity formula
	-- BatterySpawner.server.lua checks against, so this can never show a cap
	-- that disagrees with what actually stops you from picking one up.
	local carried = leaderstats.Batteries.Value
	local capacityLevel = LocalPlayer:GetAttribute("CapacityLevel") or 0
	local capacity = Upgrades.effect("Capacity", capacityLevel)
	bagLabel.Text = string.format("Batteries: %d / %d", carried, capacity)

	-- 2 & 3. Actual Cash/sec and remaining power time. "Online" reuses the
	-- exact same condition DataCenter.server.lua's payout loop checks
	-- (reserve >= powerDraw) -- DataCenterSecondsLeft is floor(reserve /
	-- powerDraw), which is > 0 precisely when that loop will pay out next
	-- tick, and 0 both when the reserve can't cover the draw AND when there's
	-- no draw to cover (no GPU equipped) -- the two cases this panel tells
	-- apart below.
	local cashPerSec, powerDraw = ownRigTotals()
	local secondsLeft = LocalPlayer:GetAttribute("DataCenterSecondsLeft") or 0
	local online = secondsLeft > 0

	if online then
		earningLabel.Text = string.format("Earning: $%d/s", cashPerSec)
		earningLabel.TextColor3 = COLOR_ONLINE
	elseif powerDraw <= 0 then
		-- No GPU installed at all -- nothing TO run, regardless of reserve.
		earningLabel.Text = "Earning: $0/s\nEquip a GPU"
		earningLabel.TextColor3 = COLOR_TEXT_DIM
	else
		-- A GPU is installed, but the banked reserve can't cover its draw.
		earningLabel.Text = string.format("Earning: $0/s (potential $%d/s)\nCollect and deposit batteries", cashPerSec)
		earningLabel.TextColor3 = COLOR_TEXT_DIM
	end

	powerLabel.Text = "Power reserve: runs " .. formatDuration(secondsLeft)

	-- 4. Next field milestone -- Fields.defs is ordered smallest/cheapest
	-- first, so the first LOCKED one in order (lifetime Cash still short of
	-- its unlockCash) is always the NEXT one, never a later one. Gated on
	-- LifetimeCash, never leaderstats.Cash, so spending never moves this bar
	-- backwards.
	local lifetime = leaderstats.LifetimeCash.Value
	local nextField = nil
	for _, def in Fields.defs do
		if lifetime < def.unlockCash then
			nextField = def
			break
		end
	end

	if nextField then
		milestoneLabel.Text = string.format(
			"Next: %s field\n$%d / $%d lifetime",
			fieldDisplayName(nextField.name), lifetime, nextField.unlockCash
		)
		local ratio = math.clamp(lifetime / nextField.unlockCash, 0, 1)
		barFill.Size = UDim2.new(ratio, 0, 1, 0)
		barBg.Visible = true
	else
		milestoneLabel.Text = "All fields unlocked."
		barBg.Visible = false
	end
end

-- ---------- the loading gate ----------
-- Several server scripts (PlayerSetup, Shop, DataCenter) each publish their
-- own piece of what this panel needs, and each waits on its own
-- PlayerData.load call that can yield (a DataStore round-trip) -- so right
-- after joining, some of these can briefly be missing entirely. Showing
-- "Loading..." instead of guessing 0s/nils as if they were real progress is
-- exactly what the spec asks for; once everything this panel reads has
-- actually shown up at least once, flip to the real content and start
-- listening for changes.
local function isDataReady()
	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	if not leaderstats then
		return false
	end
	if not (leaderstats:FindFirstChild("Batteries") and leaderstats:FindFirstChild("LifetimeCash")) then
		return false
	end
	if LocalPlayer:GetAttribute("CapacityLevel") == nil then
		return false
	end
	if LocalPlayer:GetAttribute("UnlockedSlots") == nil then
		return false
	end
	if LocalPlayer:GetAttribute("DataCenterSecondsLeft") == nil then
		return false
	end
	return true
end

local function becomeReady()
	if ready then
		return
	end
	ready = true
	loadingLabel.Visible = false
	for _, row in contentRows do
		row.Visible = true
	end
	render()
end

task.spawn(function()
	-- A short poll, not a per-frame loop -- it only runs until the handful
	-- of one-time nil -> real-value transitions above have all happened,
	-- then stops for good.
	while not isDataReady() do
		task.wait(0.25)
	end
	becomeReady()
end)

-- ---------- live updates ----------
-- Every one of these fires only when the thing it watches actually changes
-- -- no RunService.Heartbeat, no per-frame work. The running countdown's
-- once-a-second cadence comes from DataCenter.server.lua's own payout loop
-- touching "DataCenterSecondsLeft", not from anything in this script.
LocalPlayer:GetAttributeChangedSignal("DataCenterSecondsLeft"):Connect(render)
LocalPlayer:GetAttributeChangedSignal("UnlockedSlots"):Connect(render)
LocalPlayer:GetAttributeChangedSignal("CapacityLevel"):Connect(render)
for i = 1, GPUs.MAX_SLOTS do
	LocalPlayer:GetAttributeChangedSignal("Slot" .. i .. "GPU"):Connect(render)
end

task.spawn(function()
	local leaderstats = LocalPlayer:WaitForChild("leaderstats")
	leaderstats:WaitForChild("Batteries").Changed:Connect(render)
	leaderstats:WaitForChild("LifetimeCash").Changed:Connect(render)
end)
