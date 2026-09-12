--[[
	ShopUI  --  LocalScript, StarterPlayer > StarterPlayerScripts

	The upgrade shop is now TWO separate platforms (Upgrades.lua's
	`Upgrades.shops`), each with its own panel:

		PLAYER SHOP       (Workspace.Shop_Player.Pad)      -- Speed, Capacity
		DATA CENTER SHOP  (Workspace.Shop_DataCenter.Pad)  -- Efficiency, Cash

	Walk onto either pad -- actually onto its footprint, not just near it --
	and THAT platform's panel appears; walk off and it hides. Standing on
	one never shows the other. Each row shows the current effect, the
	next-level effect, and the Cash cost, with a Buy button.

	Buying just fires the BuyUpgrade RemoteEvent -- the SERVER (Shop.server.lua)
	decides if it's allowed, regardless of which pad the request came from
	(an upgrade id is an upgrade id to the server). When the server bumps our
	level (an attribute), the panel showing it refreshes.

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

-- Which Workspace pad each Upgrades.shops entry stands on, in the SAME
-- order as Upgrades.shops. World-geometry names live here, in the client
-- script that actually needs them -- not in the shared Upgrades module,
-- which only knows about upgrade ids and Cash math.
local SHOP_PAD_NAMES = { "Shop_Player", "Shop_DataCenter" }
-- ==============================================================

-- Build ONE shop's whole panel -- its own ScreenGui, title, Cash line, and
-- one row per id in `shopDef.ids` -- and wire up its Buy buttons + refresh.
-- Returns { screen, pad, refresh } for the shared show/hide loop below.
local function buildShopPanel(shopDef, padName)
	local pad = workspace:WaitForChild(padName):WaitForChild("Pad")

	local screen = Instance.new("ScreenGui")
	screen.Name = "ShopUI_" .. padName
	screen.ResetOnSpawn = false          -- survive respawns; we only build it once
	screen.Enabled = false               -- hidden until we're on this shop's pad
	screen.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	-- Tall enough for the title, Cash line, and one row per upgrade this
	-- shop carries -- the same numbers the old single 4-upgrade panel used
	-- (94 + 84*4 = 430), just generalized to however many rows a shop has.
	panel.Size = UDim2.fromOffset(400, 94 + 84 * #shopDef.ids)
	panel.BackgroundColor3 = COLOR_BG
	panel.BorderSizePixel = 0
	panel.Parent = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

	local uiPadding = Instance.new("UIPadding", panel)
	uiPadding.PaddingTop = UDim.new(0, 14)
	uiPadding.PaddingBottom = UDim.new(0, 14)
	uiPadding.PaddingLeft = UDim.new(0, 16)
	uiPadding.PaddingRight = UDim.new(0, 16)

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

	local title = label(shopDef.title, 22, COLOR_TEXT, 1)
	title.Font = Enum.Font.GothamBold
	local cashLine = label("Cash: 0", 16, COLOR_TEXT_DIM, 2)

	-- One row per upgrade id THIS shop carries. Returns { info, buy }.
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

	for i, id in shopDef.ids do
		makeRow(id, 2 + i)   -- title=1, cashLine=2, so rows start at LayoutOrder 3
	end

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

	-- Refresh when any of THIS shop's levels change (server bumped one) or our Cash changes.
	for _, id in shopDef.ids do
		LocalPlayer:GetAttributeChangedSignal(id .. "Level"):Connect(refresh)
	end
	task.spawn(function()
		local ls = LocalPlayer:WaitForChild("leaderstats")
		ls:WaitForChild("Cash").Changed:Connect(refresh)
		refresh()
	end)

	return { screen = screen, pad = pad, refresh = refresh }
end

-- Build every shop's panel up front (both start hidden).
local panels = {}
for i, shopDef in Upgrades.shops do
	table.insert(panels, buildShopPanel(shopDef, SHOP_PAD_NAMES[i]))
end

-- ---------- show / hide each panel based on actually standing on ITS OWN pad ----------
-- Same 2-D bounding-box test Fields.lua/BatterySpawner use for the battery
-- fields -- checks the pad's real footprint, not a distance-from-centre
-- radius (a radius reads past a square pad's corners and edges).
local function isOnPad(pad, position)
	local half = pad.Size / 2
	local min, max = pad.Position - half, pad.Position + half
	return position.X >= min.X and position.X <= max.X
		and position.Z >= min.Z and position.Z <= max.Z
end

RunService.Heartbeat:Connect(function()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	for _, p in panels do
		local onPad = root ~= nil and isOnPad(p.pad, root.Position)
		if onPad ~= p.screen.Enabled then
			p.screen.Enabled = onPad
			if onPad then
				p.refresh()
			end
		end
	end
end)
