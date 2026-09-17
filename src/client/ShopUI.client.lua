--[[
	ShopUI  --  LocalScript, StarterPlayer > StarterPlayerScripts

	The upgrade shop is THREE separate platforms (Upgrades.lua's
	`Upgrades.shops`), each with its own panel:

		PLAYER SHOP       (Workspace.Shop_Player.Pad)      -- Speed, Capacity
		GPU SHOP          (Workspace.Shop_GPUs.Pad)        -- the GPU catalog
		                                                       (GPUs.lua): BUY a
		                                                       card -- it always
		                                                       goes to storage;
		                                                       see
		                                                       RackShopUI.client.lua
		                                                       for how it gets
		                                                       INSTALLED
		DATA CENTER SHOP  (Workspace.Shop_DataCenter.Pad)  -- expand the data
		                                                       center's
		                                                       SPACE -- the
		                                                       ONLY thing
		                                                       this pad does
		                                                       now, as TWO
		                                                       independent
		                                                       buttons: buy
		                                                       the next
		                                                       Server_Rack
		                                                       (+4 slots,
		                                                       capped by the
		                                                       floor below),
		                                                       or upgrade the
		                                                       floor itself
		                                                       (+room for 3
		                                                       more racks)

	Walk onto any pad -- actually onto its footprint, not just near it --
	and THAT platform's panel appears; walk off and it hides. Standing on
	one never shows another.

	A shop's normal upgrade rows (Speed/Capacity) show the current effect,
	the next-level effect, and the Cash cost.
	  - Data Center Shop: TWO rows (`shopDef.spaceSection`) -- "buy the next
	    Server_Rack" (capped by the current floor) and "upgrade the floor"
	    (room for 16 more racks -- a whole physical row -- doesn't buy them).
	  - GPU Shop: one row PER GPU TYPE in the catalog (`shopDef.gpuCatalogSection`),
	    showing how many you own (equipped + stored), with a single Buy
	    button -- buying always lands in storage; INSTALLING a stored GPU
	    into a specific rack (or UNEQUIPPING one already there) happens by
	    walking up to that rack (RackShopUI.client.lua), not on either pad.
	Both panels read the SAME rig attributes off LocalPlayer, so buying a
	GPU here shows up at every rack's panel the next time you look.

	Buying anything just fires a RemoteEvent -- the SERVER (Shop.server.lua)
	decides if it's allowed. When the server publishes new attributes
	(a level, a space tier, a GPU, storage), the panel showing them refreshes.

	The whole GUI is built here in code so it lives in the repo (StarterGui is
	not part of the Rojo project).
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))
local GPUs = require(ReplicatedStorage:WaitForChild("GPUs"))
local buyEvent = ReplicatedStorage:WaitForChild("BuyUpgrade")
local buyRackEvent = ReplicatedStorage:WaitForChild("BuyServerRack")
local buyFloorEvent = ReplicatedStorage:WaitForChild("BuyDataCenterFloor")
local buyGPUEvent = ReplicatedStorage:WaitForChild("BuyGPU")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ============================ CONFIG ============================
local COLOR_BG        = Color3.fromRGB(24, 26, 32)
local COLOR_ROW       = Color3.fromRGB(36, 39, 48)
local COLOR_BUY_OK    = Color3.fromRGB(60, 190, 110)
local COLOR_BUY_NO    = Color3.fromRGB(70, 74, 84)
local COLOR_TEXT      = Color3.fromRGB(235, 237, 242)
local COLOR_TEXT_DIM  = Color3.fromRGB(160, 164, 174)

local ROW_HEIGHT = 74    -- every row, single-button
local GAP        = 10    -- vertical gap between every stacked item

-- A panel never grows taller than this -- past it, the rows scroll
-- instead. None of these three panels come close to the cap anymore
-- (Player Shop 2 rows, GPU Shop 5, Data Center Shop 2), so it's mostly
-- future headroom at this point -- kept so a panel that DOES grow tall
-- later (or a rack's, see RackShopUI.client.lua) degrades gracefully
-- instead of running off-screen.
local MAX_PANEL_HEIGHT = 560

-- title + gap + cash line -- the part of the panel that's always visible,
-- above the scrolling rows.
local TOP_BLOCK_HEIGHT = 22 + GAP + 16

-- Which Workspace pad each Upgrades.shops entry stands on, in the SAME
-- order as Upgrades.shops. World-geometry names live here, in the client
-- script that actually needs them -- not in the shared Upgrades module,
-- which only knows about upgrade ids and Cash math.
local SHOP_PAD_NAMES = { "Shop_Player", "Shop_GPUs", "Shop_DataCenter" }
-- ==============================================================

-- A bare row Frame (background + rounded corners) with an info TextLabel
-- and ONE Buy-style TextButton -- no data binding yet, just the shared
-- look every single-button row (an upgrade, or the space row) uses.
-- `onClick` fires when the button's clicked; deciding whether that click
-- should DO anything is the server's job (Shop.server.lua), not this button's.
local function makeRowFrame(panel, order, onClick)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
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

	buy.Activated:Connect(onClick)

	return { frame = row, info = info, buy = buy }
end

-- Set one button to either the "can do it" or "can't" look, with whatever
-- `text` it should show either way (a price, or a status like "Locked" /
-- "No Empty Slot" for a button that isn't just cost-gated).
local function setButtonState(button, canDo, text)
	button.Text = text
	button.BackgroundColor3 = canDo and COLOR_BUY_OK or COLOR_BUY_NO
	button.AutoButtonColor = canDo
end

local function getCashValue()
	local ls = LocalPlayer:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Cash")
	return c and c.Value or 0
end

-- Everything both the Data Center Shop and the GPU Shop need to repaint
-- themselves, read once off LocalPlayer's attributes: current Cash, the
-- current floor tier and how many racks are owned, which slots are
-- unlocked and what's installed in each, and how many of each GPU type are
-- sitting in storage. Both panels show the SAME rig from two different
-- angles, so this is one shared snapshot instead of two panels separately
-- re-reading (and re-decoding the storage JSON) every refresh.
local function getRigState()
	local cash = getCashValue()
	local floorTier = LocalPlayer:GetAttribute("FloorTier") or 1
	local racksOwned = LocalPlayer:GetAttribute("RacksOwned") or 1
	local unlocked = LocalPlayer:GetAttribute("UnlockedSlots") or (racksOwned * GPUs.SLOTS_PER_RACK)

	-- Storage is a variable-length list, so it travels as a single
	-- JSON-encoded string attribute instead of one attribute per item --
	-- decode it back into a real table here.
	local ok, storage = pcall(HttpService.JSONDecode, HttpService, LocalPlayer:GetAttribute("GPUStorageJSON") or "[]")
	if not ok or type(storage) ~= "table" then
		storage = {}
	end

	-- Read every unlocked slot's GPU id once.
	local slotGpuIds = {}
	for i = 1, unlocked do
		local id = LocalPlayer:GetAttribute("Slot" .. i .. "GPU")
		slotGpuIds[i] = (id ~= "" and id) or nil
	end

	local storedCounts = {}
	for _, id in storage do
		storedCounts[id] = (storedCounts[id] or 0) + 1
	end

	return {
		cash = cash,
		floorTier = floorTier,
		racksOwned = racksOwned,
		unlocked = unlocked,
		slotGpuIds = slotGpuIds,
		storedCounts = storedCounts,
	}
end

-- DATA CENTER SHOP: TWO rows.
--   1. "Buy Server Rack" -- the next physical rack (+GPUs.SLOTS_PER_RACK
--      slots), capped by the current floor's room (GPUs.maxRacksForTier).
--   2. "Upgrade Floor" -- room for 16 MORE racks (a whole physical row),
--      without buying them.
-- Installing or removing actual GPU hardware happens at a rack now
-- (RackShopUI.client.lua), not here. Returns a `refreshSpace()` function.
local function buildSpaceSection(panel, startOrder)
	local rackRow = makeRowFrame(panel, startOrder, function()
		buyRackEvent:FireServer()
	end)
	local floorRow = makeRowFrame(panel, startOrder + 1, function()
		buyFloorEvent:FireServer()
	end)

	local function refreshSpace()
		local cash = getCashValue()
		local floorTierIndex = LocalPlayer:GetAttribute("FloorTier") or 1
		local racksOwned = LocalPlayer:GetAttribute("RacksOwned") or 1
		local floorTier = GPUs.floorTiers[floorTierIndex]
		local nextFloorTier = GPUs.floorTiers[floorTierIndex + 1]

		-- Row 1: the next physical rack, if there's room for it.
		local nextRack = racksOwned + 1
		if nextRack > floorTier.maxRacks then
			rackRow.info.Text = string.format(
				"Server Rack %d/%d\nNo room left on this floor -- upgrade it below",
				racksOwned, floorTier.maxRacks
			)
			setButtonState(rackRow.buy, false, "No Room")
		elseif nextRack > GPUs.MAX_RACKS then
			rackRow.info.Text = string.format("Server Rack %d/%d  (MAX)", racksOwned, GPUs.MAX_RACKS)
			setButtonState(rackRow.buy, false, "MAX")
		else
			local price = GPUs.rackPrice(nextRack)
			rackRow.info.Text = string.format(
				"Server Rack %d/%d  (+%d slots)",
				racksOwned, floorTier.maxRacks, GPUs.SLOTS_PER_RACK
			)
			setButtonState(rackRow.buy, cash >= price, "Buy  $" .. price)
		end

		-- Row 2: the floor itself -- raises the ceiling row 1 can reach.
		floorRow.info.Text = string.format("Data Center Floor: %s (room for %d racks)", floorTier.name, floorTier.maxRacks)
		if nextFloorTier then
			setButtonState(floorRow.buy, cash >= nextFloorTier.price, "Upgrade  $" .. nextFloorTier.price)
		else
			setButtonState(floorRow.buy, false, "Max Floor")
		end
	end

	LocalPlayer:GetAttributeChangedSignal("FloorTier"):Connect(refreshSpace)
	LocalPlayer:GetAttributeChangedSignal("RacksOwned"):Connect(refreshSpace)

	return refreshSpace
end

-- GPU SHOP: one row per GPU TYPE in the catalog, BUY only now -- equipping
-- a stored GPU into a specific rack happens over at that rack
-- (RackShopUI.client.lua), not here. Returns a `refreshCatalog()`
-- function that repaints all of them.
local function buildGPUCatalogSection(panel, startOrder)
	-- One row per GPU TYPE (not per GPU you own) -- owning three Basics
	-- still shows one "Basic AI GPU" row, with an owned/equipped/stored
	-- count in its text. This keeps the row count fixed at 5 no matter how
	-- many duplicates a player stockpiles.
	local gpuRows = {}
	for i, gpu in GPUs.catalog do
		gpuRows[gpu.id] = makeRowFrame(panel, startOrder + i - 1, function()
			buyGPUEvent:FireServer(gpu.id)
		end)
	end

	local function refreshCatalog()
		local state = getRigState()

		for _, gpu in GPUs.catalog do
			local row = gpuRows[gpu.id]
			local equippedCount = 0
			for i = 1, state.unlocked do
				if state.slotGpuIds[i] == gpu.id then
					equippedCount += 1
				end
			end
			local storedCount = state.storedCounts[gpu.id] or 0

			row.info.Text = string.format(
				"%s  $%d  (%d Cash/s, %d mAh/s)\nOwned %d -- %d equipped, %d stored",
				gpu.name, gpu.price, gpu.cashPerSec, gpu.powerDraw,
				equippedCount + storedCount, equippedCount, storedCount
			)

			setButtonState(row.buy, state.cash >= gpu.price, "Buy  $" .. gpu.price)
		end
	end

	-- Repaint whenever the rig OR storage changes -- the owned/equipped/
	-- stored counts shown here depend on all of it, even though buying
	-- itself only ever touches storage.
	LocalPlayer:GetAttributeChangedSignal("UnlockedSlots"):Connect(refreshCatalog)
	LocalPlayer:GetAttributeChangedSignal("GPUStorageJSON"):Connect(refreshCatalog)
	for i = 1, GPUs.MAX_SLOTS do
		LocalPlayer:GetAttributeChangedSignal("Slot" .. i .. "GPU"):Connect(refreshCatalog)
	end

	return refreshCatalog
end

-- Build ONE shop's whole panel -- its own ScreenGui, title, Cash line, one
-- row per id in `shopDef.ids`, and (if `shopDef.spaceSection` or
-- `shopDef.gpuCatalogSection`) that shop's extra section.
-- Returns { screen, pad, refresh } for the show/hide loop.
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
	panel.Size = UDim2.fromOffset(400, TOP_BLOCK_HEIGHT + 28)   -- placeholder -- fitPanelHeight() sets the real size below, once rows exist
	panel.BackgroundColor3 = COLOR_BG
	panel.BorderSizePixel = 0
	panel.Parent = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

	local uiPadding = Instance.new("UIPadding", panel)
	uiPadding.PaddingTop = UDim.new(0, 14)
	uiPadding.PaddingBottom = UDim.new(0, 14)
	uiPadding.PaddingLeft = UDim.new(0, 16)
	uiPadding.PaddingRight = UDim.new(0, 16)

	local function label(text, size, color, order)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(0, order == 1 and 0 or 22 + GAP)
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

	-- Everything below the title/cash line lives in a ScrollingFrame, so
	-- when there are more rows than MAX_PANEL_HEIGHT can show, you scroll
	-- to reach them instead of them just running off-screen.
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "Rows"
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.Position = UDim2.fromOffset(0, TOP_BLOCK_HEIGHT + GAP)
	scrollFrame.Size = UDim2.new(1, 0, 1, -(TOP_BLOCK_HEIGHT + GAP))
	scrollFrame.CanvasSize = UDim2.fromOffset(0, 0)      -- grown automatically, below
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = COLOR_TEXT_DIM
	scrollFrame.Parent = panel

	local rowsLayout = Instance.new("UIListLayout", scrollFrame)
	rowsLayout.Padding = UDim.new(0, GAP)
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder

	-- Resize the panel to fit however tall its rows currently measure --
	-- capped at MAX_PANEL_HEIGHT, past which the ScrollingFrame scrolls
	-- instead. Driven by the row layout's OWN measured size (rather than a
	-- hand-computed one) so a panel resizes itself automatically if its
	-- row count or wrapped-text height ever changes, not just once at startup.
	local function fitPanelHeight()
		local naturalHeight = 28 + TOP_BLOCK_HEIGHT + GAP + rowsLayout.AbsoluteContentSize.Y
		panel.Size = UDim2.fromOffset(400, math.min(naturalHeight, MAX_PANEL_HEIGHT))
	end
	rowsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitPanelHeight)

	-- One row per upgrade id THIS shop carries.
	local rows = {}
	for i, id in shopDef.ids do
		rows[id] = makeRowFrame(scrollFrame, i, function()
			buyEvent:FireServer(id)   -- ask the server; it decides
		end)
	end

	-- The space section (just the one row) or the GPU catalog section (one
	-- row per GPU type) goes after the normal upgrade rows, if this shop
	-- has one -- never both; each lives on its own pad.
	local refreshSpace, refreshCatalog
	if shopDef.spaceSection then
		refreshSpace = buildSpaceSection(scrollFrame, #shopDef.ids + 1)
	end
	if shopDef.gpuCatalogSection then
		refreshCatalog = buildGPUCatalogSection(scrollFrame, #shopDef.ids + 1)
	end

	fitPanelHeight()   -- size correctly before this panel is ever shown

	local function refresh()
		local cash = getCashValue()
		cashLine.Text = "Cash: " .. cash

		for id, row in rows do
			local level = LocalPlayer:GetAttribute(id .. "Level") or 0
			local def = Upgrades.defs[id]
			local now = Upgrades.formatEffect(id, Upgrades.effect(id, level))

			if level >= def.maxLevel then
				-- Topped out -- nothing left to preview or buy.
				row.info.Text = string.format("%s  (lvl %d/%d -- MAX)\n%s", def.name, level, def.maxLevel, now)
				setButtonState(row.buy, false, "MAX")
			else
				local cost = Upgrades.cost(id, level)
				local nextt = Upgrades.formatEffect(id, Upgrades.effect(id, level + 1))
				row.info.Text = string.format("%s  (lvl %d/%d)\n%s  →  %s", def.name, level, def.maxLevel, now, nextt)
				setButtonState(row.buy, cash >= cost, "Buy  $" .. cost)
			end
		end

		if refreshSpace then
			refreshSpace()
		end
		if refreshCatalog then
			refreshCatalog()
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
