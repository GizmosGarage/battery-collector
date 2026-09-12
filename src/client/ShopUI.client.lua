--[[
	ShopUI  --  LocalScript, StarterPlayer > StarterPlayerScripts

	The upgrade shop's screen. Walk onto Workspace.Shop.Pad -- actually onto
	its footprint, not just near it -- and this panel appears; walk off and
	it hides. One row per upgrade in Upgrades.order. Each shows the current
	effect, the next-level effect, and the Cash cost, with a Buy button.

	Buying just fires the BuyUpgrade RemoteEvent -- the SERVER (Shop.server.lua)
	decides if it's allowed. When the server bumps our level (an attribute), the
	panel refreshes.

	The whole GUI is built here in code so it lives in the repo (StarterGui is
	not part of the Rojo project).
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))
local buyEvent = ReplicatedStorage:WaitForChild("BuyUpgrade")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ============================ CONFIG ============================
local COLOR_BG        = Color3.fromRGB(24, 26, 32)
local COLOR_ROW       = Color3.fromRGB(36, 39, 48)
local COLOR_BUY_OK    = Color3.fromRGB(60, 190, 110)
local COLOR_BUY_NO    = Color3.fromRGB(70, 74, 84)
local COLOR_TEXT      = Color3.fromRGB(235, 237, 242)
local COLOR_TEXT_DIM  = Color3.fromRGB(160, 164, 174)
-- ==============================================================

local shop = workspace:WaitForChild("Shop")
local shopPad = shop:WaitForChild("Pad")

-- ---------- build the GUI ----------
local screen = Instance.new("ScreenGui")
screen.Name = "ShopUI"
screen.ResetOnSpawn = false          -- survive respawns; we only build it once
screen.Enabled = false               -- hidden until we're near the pad
screen.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(400, 430)   -- tall enough for the title, Cash line, and 4 rows
panel.BackgroundColor3 = COLOR_BG
panel.BorderSizePixel = 0
panel.Parent = screen
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local pad = Instance.new("UIPadding", panel)
pad.PaddingTop = UDim.new(0, 14)
pad.PaddingBottom = UDim.new(0, 14)
pad.PaddingLeft = UDim.new(0, 16)
pad.PaddingRight = UDim.new(0, 16)

local layout = Instance.new("UIListLayout", panel)
layout.Padding = UDim.new(0, 10)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local function label(text, size, color, order)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, size)
	l.Font = Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.LayoutOrder = order
	l.Parent = panel
	return l
end

local title = label("UPGRADE SHOP", 22, COLOR_TEXT, 1)
title.Font = Enum.Font.GothamBold
local cashLine = label("Cash: 0", 16, COLOR_TEXT_DIM, 2)

-- One row per upgrade id. Returns { info = TextLabel, buy = TextButton }.
local rows = {}
local function makeRow(id, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 74)
	row.BackgroundColor3 = COLOR_ROW
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = panel
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1
	info.Position = UDim2.fromOffset(12, 8)
	info.Size = UDim2.new(1, -24, 0, 40)
	info.Font = Enum.Font.GothamMedium
	info.TextSize = 14
	info.TextColor3 = COLOR_TEXT
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.TextWrapped = true
	info.Text = ""
	info.Parent = row

	local buy = Instance.new("TextButton")
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Position = UDim2.new(1, -12, 1, -10)
	buy.Size = UDim2.fromOffset(120, 26)
	buy.Font = Enum.Font.GothamBold
	buy.TextSize = 14
	buy.TextColor3 = COLOR_TEXT
	buy.BackgroundColor3 = COLOR_BUY_NO
	buy.BorderSizePixel = 0
	buy.AutoButtonColor = false
	buy.Text = "Buy"
	buy.Parent = row
	Instance.new("UICorner", buy).CornerRadius = UDim.new(0, 6)

	buy.Activated:Connect(function()
		buyEvent:FireServer(id)   -- ask the server; it decides
	end)

	rows[id] = { info = info, buy = buy }
end

for i, id in Upgrades.order do
	makeRow(id, 2 + i)   -- title=1, cashLine=2, so rows start at LayoutOrder 3
end

-- ---------- keep the numbers current ----------
local function getCashValue()
	local ls = LocalPlayer:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Cash")
	return c and c.Value or 0
end

local function refresh()
	local cash = getCashValue()
	cashLine.Text = "Cash: " .. cash

	for id, row in rows do
		local level = LocalPlayer:GetAttribute(id .. "Level") or 0
		local cost = Upgrades.cost(id, level)
		local now = Upgrades.formatEffect(id, Upgrades.effect(id, level))
		local nextt = Upgrades.formatEffect(id, Upgrades.effect(id, level + 1))
		local def = Upgrades.defs[id]

		row.info.Text = string.format("%s  (lvl %d)\n%s  →  %s", def.name, level, now, nextt)

		local canAfford = cash >= cost
		row.buy.Text = "Buy  $" .. cost
		row.buy.BackgroundColor3 = canAfford and COLOR_BUY_OK or COLOR_BUY_NO
		row.buy.AutoButtonColor = canAfford
	end
end

-- Refresh when any of our levels change (server bumped one) or our Cash changes.
for _, id in Upgrades.order do
	LocalPlayer:GetAttributeChangedSignal(id .. "Level"):Connect(refresh)
end
task.spawn(function()
	local ls = LocalPlayer:WaitForChild("leaderstats")
	ls:WaitForChild("Cash").Changed:Connect(refresh)
	refresh()
end)

-- ---------- show / hide based on actually standing on the pad ----------
-- A plain radius check used to open this at 12 studs from the pad's CENTRE --
-- for a 12x12 pad that's a circle poking out past every edge, so it could
-- pop open while still standing well off the platform. This checks the
-- pad's real footprint instead (same 2-D bounding-box test Fields.lua and
-- BatterySpawner use for the battery fields), so it only shows once you're
-- actually on it.
local function isOnPad(position)
	local half = shopPad.Size / 2
	local min, max = shopPad.Position - half, shopPad.Position + half
	return position.X >= min.X and position.X <= max.X
		and position.Z >= min.Z and position.Z <= max.Z
end

RunService.Heartbeat:Connect(function()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local onPad = root ~= nil and isOnPad(root.Position)

	if onPad ~= screen.Enabled then
		screen.Enabled = onPad
		if onPad then
			refresh()
		end
	end
end)
