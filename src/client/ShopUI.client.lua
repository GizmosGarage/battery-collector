--[[
	ShopUI  --  LocalScript, StarterPlayer > StarterPlayerScripts

	The upgrade shop is THREE separate platforms (Upgrades.lua's
	`Upgrades.shops`), each with its own panel:

		PLAYER SHOP       (Workspace.Shop_Player.Pad)      -- Speed, Capacity
		GPU SHOP          (Workspace.Shop_GPUs.Pad)        -- the GPU catalog
		                                                       (GPUs.lua): buy a
		                                                       card, or equip one
		                                                       you already own
		                                                       from storage
		DATA CENTER SHOP  (Workspace.Shop_DataCenter.Pad)  -- expand the data
		                                                       center's SPACE
		                                                       (raises how many
		                                                       slots it could
		                                                       ever hold), buy
		                                                       an individual
		                                                       SLOT within that
		                                                       space, and see/
		                                                       unequip whatever's
		                                                       installed in each
		                                                       one you have

	Walk onto any pad -- actually onto its footprint, not just near it --
	and THAT platform's panel appears; walk off and it hides. Standing on
	one never shows another.

	A shop's normal upgrade rows (Speed/Capacity) show the current effect,
	the next-level effect, and the Cash cost. The GPU Shop and Data Center
	Shop each get ONE HALF of the GPU system, split so neither panel has to
	cram a catalog together with the space/slot rows into one scroll
	(`shopDef.gpuCatalogSection` / `shopDef.slotsSection`):
	  - Data Center Shop: a "Data Center Space" row (current tier + an
	    Expand button for the next one), an "Installed Slots" row (X / the
	    current tier's max, with a Buy Slot button), then one row PER
	    INSTALLED slot, showing what's in it with an Unequip button. Space
	    and slots are two SEPARATE purchases on purpose -- buying more
	    space only raises the slot ceiling, it doesn't hand you a slot;
	    every slot past the first still costs its own flat price.
	  - GPU Shop: one row PER GPU TYPE in the catalog, showing how many you
	    own (equipped + stored), with a Buy button (always available if you
	    can afford it -- it auto-installs into an empty slot, or goes to
	    storage if the rig's full) and an Equip button (moves a spare out
	    of storage into an empty slot) that previews the resulting total
	    Cash/sec right on the button
	Both panels read the SAME rig attributes off LocalPlayer, so buying a
	GPU on one pad shows up on the other the next time you walk onto it.
	Equipping and unequipping are both FREE -- together they're how you
	swap a worse card for a better one: unequip the old (Data Center Shop),
	equip the new (GPU Shop).

	Buying anything just fires a RemoteEvent -- the SERVER (Shop.server.lua)
	decides if it's allowed. When the server publishes new attributes
	(a level, a slot, a GPU, storage), the panel showing them refreshes.

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
local buySpaceEvent = ReplicatedStorage:WaitForChild("BuyDataCenterSpace")
local buySlotEvent = ReplicatedStorage:WaitForChild("BuyGPUSlot")
local buyGPUEvent = ReplicatedStorage:WaitForChild("BuyGPU")
local equipGPUEvent = ReplicatedStorage:WaitForChild("EquipGPU")
local unequipGPUEvent = ReplicatedStorage:WaitForChild("UnequipGPU")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ============================ CONFIG ============================
local COLOR_BG        = Color3.fromRGB(24, 26, 32)
local COLOR_ROW       = Color3.fromRGB(36, 39, 48)
local COLOR_BUY_OK    = Color3.fromRGB(60, 190, 110)
local COLOR_BUY_NO    = Color3.fromRGB(70, 74, 84)
local COLOR_TEXT      = Color3.fromRGB(235, 237, 242)
local COLOR_TEXT_DIM  = Color3.fromRGB(160, 164, 174)

local ROW_HEIGHT     = 74    -- a normal, single-button row
local GPU_ROW_HEIGHT = 112   -- a catalog row: taller, has TWO buttons (Buy + Equip)
local GAP            = 10    -- vertical gap between every stacked item

-- A panel never grows taller than this -- past it, the rows scroll instead.
-- The GPU Shop's 5 catalog rows (each 112px, two buttons apiece) add up to
-- way more than this, which is exactly why it needs to scroll; the Player
-- Shop's 2 rows never get close to the cap, so its panel just stays its
-- natural, shorter height.
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
-- look every single-button row (upgrade, slot-unlock, or per-slot
-- Unequip) uses. `onClick` fires when the button's clicked; deciding
-- whether that click should DO anything is the server's job
-- (Shop.server.lua), not this button's.
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

-- A row with TWO buttons stacked bottom-right (Buy above, Equip above
-- that) -- used only for the GPU catalog, where one type needs both
-- "buy another" and "equip a spare from storage" as separate actions.
local function makeGPURow(panel, order, onBuy, onEquip)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, GPU_ROW_HEIGHT)
	row.BackgroundColor3 = COLOR_ROW
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = panel
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1
	info.Position = UDim2.fromOffset(12, 8)
	info.Size = UDim2.new(1, -24, 0, 60)
	info.Font = Enum.Font.GothamMedium
	info.TextSize = 14
	info.TextColor3 = COLOR_TEXT
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.TextWrapped = true
	info.Text = ""
	info.Parent = row

	local function makeButton(bottomOffset)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(1, 1)
		b.Position = UDim2.new(1, -12, 1, bottomOffset)
		b.Size = UDim2.fromOffset(150, 26)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 13
		b.TextColor3 = COLOR_TEXT
		b.BackgroundColor3 = COLOR_BUY_NO
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.Text = "Buy"
		b.Parent = row
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
		return b
	end

	local buy = makeButton(-10)
	buy.Activated:Connect(onBuy)

	local equip = makeButton(-42)
	equip.Activated:Connect(onEquip)

	return { info = info, buy = buy, equip = equip }
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
-- current space tier, which slots are unlocked and what's installed in
-- each, and how many of each GPU type are sitting in storage. Both panels
-- show the SAME rig from two different angles, so this is one shared
-- snapshot instead of two panels separately re-reading (and re-decoding
-- the storage JSON) every refresh.
local function getRigState()
	local cash = getCashValue()
	local spaceTier = LocalPlayer:GetAttribute("SpaceTier") or 1
	local unlocked = LocalPlayer:GetAttribute("UnlockedSlots") or 1

	-- Storage is a variable-length list, so it travels as a single
	-- JSON-encoded string attribute instead of one attribute per item --
	-- decode it back into a real table here.
	local ok, storage = pcall(HttpService.JSONDecode, HttpService, LocalPlayer:GetAttribute("GPUStorageJSON") or "[]")
	if not ok or type(storage) ~= "table" then
		storage = {}
	end

	-- Read every unlocked slot's GPU id once, and total up the rig's
	-- CURRENT combined Cash/sec -- this is what the GPU Shop's Equip
	-- button preview shows the change FROM.
	local slotGpuIds, totalCash, hasEmptySlot = {}, 0, false
	for i = 1, unlocked do
		local id = LocalPlayer:GetAttribute("Slot" .. i .. "GPU")
		slotGpuIds[i] = (id ~= "" and id) or nil
		if slotGpuIds[i] then
			totalCash += GPUs.get(slotGpuIds[i]).cashPerSec
		else
			hasEmptySlot = true
		end
	end

	local storedCounts = {}
	for _, id in storage do
		storedCounts[id] = (storedCounts[id] or 0) + 1
	end

	return {
		cash = cash,
		spaceTier = spaceTier,
		unlocked = unlocked,
		slotGpuIds = slotGpuIds,
		totalCash = totalCash,
		hasEmptySlot = hasEmptySlot,
		storedCounts = storedCounts,
	}
end

-- DATA CENTER SHOP: a "Data Center Space" row, an "Installed Slots" row,
-- then one row per INSTALLED slot. Returns a `refreshSlots()` function
-- that repaints all of them.
local function buildSlotsSection(panel, startOrder)
	local spaceRow = makeRowFrame(panel, startOrder, function()
		buySpaceEvent:FireServer()
	end)

	local slotBuyRow = makeRowFrame(panel, startOrder + 1, function()
		buySlotEvent:FireServer()
	end)

	-- One row per INSTALLED slot -- unlike the old fixed 1-4 slot range,
	-- a space expansion can push this up to 32, so rows are added/removed
	-- to match instead of a fixed-size array with "Locked" placeholders.
	-- `#slotRows` IS the row count -- `ensureSlotRowCount` just grows or
	-- shrinks it to match how many slots are actually unlocked.
	local slotRows = {}
	local function ensureSlotRowCount(count)
		for i = #slotRows + 1, count do
			slotRows[i] = makeRowFrame(panel, startOrder + 1 + i, function()
				unequipGPUEvent:FireServer(i)
			end)
		end
		for i = #slotRows, count + 1, -1 do
			slotRows[i].frame:Destroy()
			slotRows[i] = nil
		end
	end

	local function refreshSlots()
		local state = getRigState()
		local tier = GPUs.spaceTiers[state.spaceTier]
		local nextTier = GPUs.spaceTiers[state.spaceTier + 1]

		-- ---- the "data center space" row ----
		spaceRow.info.Text = string.format("Data Center Space: %s (%d slots max)", tier.name, tier.maxSlots)
		if nextTier then
			setButtonState(spaceRow.buy, state.cash >= nextTier.price, "Expand  $" .. nextTier.price)
		else
			setButtonState(spaceRow.buy, false, "Max Space")
		end

		-- ---- the "installed slots" summary row ----
		slotBuyRow.info.Text = string.format("Installed Slots: %d / %d", state.unlocked, tier.maxSlots)
		if state.unlocked >= tier.maxSlots then
			setButtonState(slotBuyRow.buy, false, "Space Full")
		else
			setButtonState(slotBuyRow.buy, state.cash >= GPUs.SLOT_PRICE, "Buy Slot  $" .. GPUs.SLOT_PRICE)
		end

		-- ---- one row per installed slot: what's in it, and Unequip it ----
		ensureSlotRowCount(state.unlocked)
		for i = 1, state.unlocked do
			local row = slotRows[i]
			local gpu = state.slotGpuIds[i] and GPUs.get(state.slotGpuIds[i])
			if gpu then
				row.info.Text = string.format(
					"Slot %d: %s\n%d Cash/sec, %d mAh/s power",
					i, gpu.name, gpu.cashPerSec, gpu.powerDraw
				)
				setButtonState(row.buy, true, "Unequip")   -- always free, so always "doable"
			else
				row.info.Text = string.format("Slot %d: Empty", i)
				setButtonState(row.buy, false, "Empty")
			end
		end
	end

	-- Repaint whenever the rig's space or slots (unlocked count, or what's
	-- in each one) change -- storage doesn't affect anything shown here.
	LocalPlayer:GetAttributeChangedSignal("SpaceTier"):Connect(refreshSlots)
	LocalPlayer:GetAttributeChangedSignal("UnlockedSlots"):Connect(refreshSlots)
	for i = 1, GPUs.MAX_SLOTS do
		LocalPlayer:GetAttributeChangedSignal("Slot" .. i .. "GPU"):Connect(refreshSlots)
	end

	return refreshSlots
end

-- GPU SHOP: one row per GPU TYPE in the catalog. Returns a
-- `refreshCatalog()` function that repaints all of them.
local function buildGPUCatalogSection(panel, startOrder)
	-- One row per GPU TYPE (not per GPU you own) -- owning three Basics
	-- still shows one "Basic AI GPU" row, with an owned/equipped/stored
	-- count in its text. This keeps the row count fixed at 5 no matter how
	-- many duplicates a player stockpiles.
	local gpuRows = {}
	for i, gpu in GPUs.catalog do
		gpuRows[gpu.id] = makeGPURow(panel, startOrder + i - 1, function()
			buyGPUEvent:FireServer(gpu.id)
		end, function()
			equipGPUEvent:FireServer(gpu.id)
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

			if storedCount == 0 then
				setButtonState(row.equip, false, "None Stored")
			elseif not state.hasEmptySlot then
				setButtonState(row.equip, false, "No Empty Slot")
			else
				-- The preview: exactly what "show how total Cash/sec would
				-- change" means here -- the button itself says the before
				-- and after, so equipping is never a guess.
				setButtonState(
					row.equip, true,
					string.format("Equip (%d->%d/s)", state.totalCash, state.totalCash + gpu.cashPerSec)
				)
			end
		end
	end

	-- Repaint whenever the rig OR storage changes -- a catalog row's Equip
	-- button depends on ALL of these (empty-slot availability, the Cash/sec
	-- preview, and how many of this type are stored).
	LocalPlayer:GetAttributeChangedSignal("UnlockedSlots"):Connect(refreshCatalog)
	LocalPlayer:GetAttributeChangedSignal("GPUStorageJSON"):Connect(refreshCatalog)
	for i = 1, GPUs.MAX_SLOTS do
		LocalPlayer:GetAttributeChangedSignal("Slot" .. i .. "GPU"):Connect(refreshCatalog)
	end

	return refreshCatalog
end

-- Build ONE shop's whole panel -- its own ScreenGui, title, Cash line, one
-- row per id in `shopDef.ids`, and (if `shopDef.slotsSection` or
-- `shopDef.gpuCatalogSection`) that shop's half of the GPU system.
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
	-- hand-computed one) so a shop whose row COUNT changes during play
	-- (the Data Center Shop's per-slot rows, as you buy more) resizes
	-- itself automatically, not just once at startup.
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

	-- The slots section (slot-unlock row + per-slot rows) or the GPU
	-- catalog section (one row per GPU type) goes after the normal upgrade
	-- rows, if this shop has one -- never both; each lives on its own pad.
	local refreshSlots, refreshCatalog
	if shopDef.slotsSection then
		refreshSlots = buildSlotsSection(scrollFrame, #shopDef.ids + 1)
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
			local cost = Upgrades.cost(id, level)
			local now = Upgrades.formatEffect(id, Upgrades.effect(id, level))
			local nextt = Upgrades.formatEffect(id, Upgrades.effect(id, level + 1))
			local def = Upgrades.defs[id]

			row.info.Text = string.format("%s  (lvl %d)\n%s  →  %s", def.name, level, now, nextt)
			setButtonState(row.buy, cash >= cost, "Buy  $" .. cost)
		end

		if refreshSlots then
			refreshSlots()
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
