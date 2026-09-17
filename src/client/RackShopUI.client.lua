--[[
	RackShopUI  --  LocalScript, StarterPlayer > StarterPlayerScripts

	Where GPU hardware actually gets managed now. Buying at the GPU Shop
	(ShopUI.client.lua) only ever puts a card into STORAGE, and the Data
	Center Shop only expands SPACE -- moving hardware between a slot and
	storage, in either direction, happens here, by walking up to the
	specific Server_Rack you want to change. Get close to one and a panel
	appears showing that rack's own 4 slots (installed or empty, with an
	Unequip button) AND every GPU type you have in storage (with an
	"Equip Here" button that fills the first empty slot THAT rack owns).

	Same "walk up, panel appears" idea as the shop pads (ShopUI.client.lua)
	and the same per-rack numbering GPURackDisplay.client.lua uses to show
	the right physical card in the right slot: every Server_Rack in
	Workspace, in GPUs.sortRacks order (column first left-to-right, then
	row within a column front-to-back), is rack 1, 2, 3... and
	GPUs.rackSlotRange turns a rack number into the flat "Slot<N>GPU" range
	it owns (GPUs.SLOTS_PER_RACK per rack). The SERVER
	(Shop.server.lua's equipGPUEvent) re-derives that same range from the
	rack number this script sends -- it never needs to know where a rack
	actually sits in the world. Unequipping doesn't need a range at all --
	unequipGPUEvent already takes a plain slot number, and every slot this
	panel shows already belongs to this one rack.

	Unlike a shop pad (a flat platform you stand ON), a rack is a tall
	shelf you walk UP TO -- so instead of a "standing on this pad's
	footprint" test, this uses plain distance: whichever rack is CLOSEST
	within PROXIMITY_RADIUS gets its panel shown, and only that one, so
	standing between two racks never pops up both at once.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local GPUs = require(ReplicatedStorage:WaitForChild("GPUs"))
local equipGPUEvent = ReplicatedStorage:WaitForChild("EquipGPU")
local unequipGPUEvent = ReplicatedStorage:WaitForChild("UnequipGPU")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ============================ CONFIG ============================
-- Same palette as ShopUI.client.lua, so this reads as part of the same
-- shop system even though it lives at a different kind of location.
local COLOR_BG        = Color3.fromRGB(24, 26, 32)
local COLOR_ROW       = Color3.fromRGB(36, 39, 48)
local COLOR_BUY_OK    = Color3.fromRGB(60, 190, 110)
local COLOR_BUY_NO    = Color3.fromRGB(70, 74, 84)
local COLOR_TEXT      = Color3.fromRGB(235, 237, 242)
local COLOR_TEXT_DIM  = Color3.fromRGB(160, 164, 174)

local ROW_HEIGHT = 74
local GAP        = 10
local PANEL_WIDTH = 400
local TOP_BLOCK_HEIGHT = 22 + GAP + 16

-- A panel never grows taller than this -- past it, the rows scroll
-- instead. 4 installed rows + 5 storage rows + 2 section headers adds up
-- to well more than a short panel, so unlike ShopUI's three shop panels,
-- this one routinely needs to scroll.
local MAX_PANEL_HEIGHT = 560

local PROXIMITY_RADIUS = 6   -- studs -- close enough to a rack to see its panel
-- ==============================================================

-- The racks (and the slots each one owns) are Workspace content that
-- streams in separately from this script -- wait for at least the first
-- one, same reason GPURackDisplay.client.lua does.
workspace:WaitForChild("Server_Rack", 10)

-- Every Server_Rack in the world, in GPUs.sortRacks order -- rack 1, rack
-- 2, ... in the SAME order GPURackDisplay.client.lua numbers them, so
-- "rack 2's panel" and "rack 2's physical cards" always agree on which
-- slots that means.
local unsortedRacks = {}
for _, child in workspace:GetChildren() do
	if child.Name == "Server_Rack" and child:IsA("BasePart") then
		table.insert(unsortedRacks, child)
	end
end
local racks = GPUs.sortRacks(unsortedRacks)

-- ---------- shared row-building helpers (same look as ShopUI.client.lua) ----------
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

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -12, 1, -10)
	button.Size = UDim2.fromOffset(140, 26)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextColor3 = COLOR_TEXT
	button.BackgroundColor3 = COLOR_BUY_NO
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = row
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)

	button.Activated:Connect(onClick)

	return { info = info, button = button }
end

-- A small non-interactive label that separates the two sections of a
-- rack's panel ("INSTALLED" / "IN STORAGE") -- same idea as a shop
-- panel's title, just smaller and mid-list.
local function makeSectionHeader(panel, order, text)
	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 18)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 13
	header.TextColor3 = COLOR_TEXT_DIM
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = text
	header.LayoutOrder = order
	header.Parent = panel
	return header
end

local function setButtonState(button, canDo, text)
	button.Text = text
	button.BackgroundColor3 = canDo and COLOR_BUY_OK or COLOR_BUY_NO
	button.AutoButtonColor = canDo
end

-- How many of each GPU type this player currently has in storage.
local function storedCounts()
	local ok, storage = pcall(HttpService.JSONDecode, HttpService, LocalPlayer:GetAttribute("GPUStorageJSON") or "[]")
	if not ok or type(storage) ~= "table" then
		storage = {}
	end
	local counts = {}
	for _, id in storage do
		counts[id] = (counts[id] or 0) + 1
	end
	return counts
end

-- Whether THIS rack (by number) has anywhere left to put a GPU right now --
-- "locked" (none of its slots are unlocked yet), "full" (all its unlocked
-- slots already have a card), or "open" (at least one doesn't).
local function rackStatus(rangeStart, rangeEnd)
	local unlocked = LocalPlayer:GetAttribute("UnlockedSlots") or 0
	if rangeStart > unlocked then
		return "locked"
	end
	for i = rangeStart, math.min(rangeEnd, unlocked) do
		if (LocalPlayer:GetAttribute("Slot" .. i .. "GPU") or "") == "" then
			return "open"
		end
	end
	return "full"
end

-- INSTALLED section: one fixed row per slot this rack owns -- what's in
-- it (if anything) and an Unequip button. Returns a `refresh()` function.
local function buildInstalledSection(panel, startOrder, rangeStart, rangeEnd)
	local rows = {}
	for i = rangeStart, rangeEnd do
		rows[i] = makeRowFrame(panel, startOrder + (i - rangeStart), function()
			unequipGPUEvent:FireServer(i)
		end)
	end

	local function refresh()
		local unlocked = LocalPlayer:GetAttribute("UnlockedSlots") or 0
		for i = rangeStart, rangeEnd do
			local row = rows[i]
			if i > unlocked then
				-- This slot doesn't exist yet -- the player hasn't bought
				-- enough SPACE (Data Center Shop) to cover it.
				row.info.Text = string.format("Slot %d: Locked", i)
				setButtonState(row.button, false, "Locked")
			else
				local id = LocalPlayer:GetAttribute("Slot" .. i .. "GPU")
				local gpu = id ~= "" and GPUs.get(id)
				if gpu then
					row.info.Text = string.format(
						"Slot %d: %s\n%d Cash/sec, %d mAh/s power",
						i, gpu.name, gpu.cashPerSec, gpu.powerDraw
					)
					setButtonState(row.button, true, "Unequip")   -- always free, so always "doable"
				else
					row.info.Text = string.format("Slot %d: Empty", i)
					setButtonState(row.button, false, "Empty")
				end
			end
		end
	end

	return refresh
end

-- IN STORAGE section: one row per GPU TYPE in the catalog -- same
-- fixed-row-count idea as the GPU Shop's own catalog, so owning three
-- Basics still shows one row. Returns a `refresh()` function.
local function buildStorageSection(panel, startOrder, rackIndex, rangeStart, rangeEnd)
	local rows = {}
	for i, gpu in GPUs.catalog do
		rows[gpu.id] = makeRowFrame(panel, startOrder + i - 1, function()
			equipGPUEvent:FireServer(gpu.id, rackIndex)
		end)
	end

	local function refresh()
		local counts = storedCounts()
		local status = rackStatus(rangeStart, rangeEnd)

		for _, gpu in GPUs.catalog do
			local row = rows[gpu.id]
			local count = counts[gpu.id] or 0

			row.info.Text = string.format(
				"%s  (%d Cash/s, %d mAh/s)\n%d stored",
				gpu.name, gpu.cashPerSec, gpu.powerDraw, count
			)

			if count <= 0 then
				setButtonState(row.button, false, "None Stored")
			elseif status == "locked" then
				setButtonState(row.button, false, "No Slots Unlocked")
			elseif status == "full" then
				setButtonState(row.button, false, "Rack Full")
			else
				setButtonState(row.button, true, "Equip Here")
			end
		end
	end

	return refresh
end

-- ---------- build one rack's whole panel ----------
local function buildRackPanel(rackIndex)
	local rangeStart, rangeEnd = GPUs.rackSlotRange(rackIndex)

	local screen = Instance.new("ScreenGui")
	screen.Name = "RackShopUI_" .. rackIndex
	screen.ResetOnSpawn = false
	screen.Enabled = false
	screen.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, TOP_BLOCK_HEIGHT + 28)   -- placeholder -- fitPanelHeight() sets the real size below
	panel.BackgroundColor3 = COLOR_BG
	panel.BorderSizePixel = 0
	panel.Parent = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

	local uiPadding = Instance.new("UIPadding", panel)
	uiPadding.PaddingTop = UDim.new(0, 14)
	uiPadding.PaddingBottom = UDim.new(0, 14)
	uiPadding.PaddingLeft = UDim.new(0, 16)
	uiPadding.PaddingRight = UDim.new(0, 16)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 0)
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = COLOR_TEXT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = string.format("SERVER RACK %d", rackIndex)
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(0, 22 + GAP)
	subtitle.Size = UDim2.new(1, 0, 0, 16)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 16
	subtitle.TextColor3 = COLOR_TEXT_DIM
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = string.format("Slots %d-%d", rangeStart, rangeEnd)
	subtitle.Parent = panel

	-- Everything below the title/subtitle lives in a ScrollingFrame, same
	-- as every ShopUI.client.lua panel -- see MAX_PANEL_HEIGHT above.
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

	local function fitPanelHeight()
		local naturalHeight = 28 + TOP_BLOCK_HEIGHT + GAP + rowsLayout.AbsoluteContentSize.Y
		panel.Size = UDim2.fromOffset(PANEL_WIDTH, math.min(naturalHeight, MAX_PANEL_HEIGHT))
	end
	rowsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitPanelHeight)

	-- INSTALLED: a header, then GPUs.SLOTS_PER_RACK rows (LayoutOrder 1..N+1).
	makeSectionHeader(scrollFrame, 1, "INSTALLED")
	local refreshInstalled = buildInstalledSection(scrollFrame, 2, rangeStart, rangeEnd)

	-- IN STORAGE: a header, then one row per catalog GPU type, right after.
	local storageHeaderOrder = 2 + GPUs.SLOTS_PER_RACK
	makeSectionHeader(scrollFrame, storageHeaderOrder, "IN STORAGE")
	local refreshStorage = buildStorageSection(scrollFrame, storageHeaderOrder + 1, rackIndex, rangeStart, rangeEnd)

	fitPanelHeight()   -- size correctly before this panel is ever shown

	local function refresh()
		refreshInstalled()
		refreshStorage()
	end

	-- Repaint whenever storage, unlocked slots, or any of THIS rack's own
	-- slots change -- other racks' slots don't affect this panel at all.
	LocalPlayer:GetAttributeChangedSignal("GPUStorageJSON"):Connect(refresh)
	LocalPlayer:GetAttributeChangedSignal("UnlockedSlots"):Connect(refresh)
	for i = rangeStart, rangeEnd do
		LocalPlayer:GetAttributeChangedSignal("Slot" .. i .. "GPU"):Connect(refresh)
	end

	return { screen = screen, rackPart = racks[rackIndex], refresh = refresh }
end

local panels = {}
for i in racks do
	table.insert(panels, buildRackPanel(i))
end

-- ---------- show only the CLOSEST rack's panel, and only within range ----------
-- A rack past this player's "RacksOwned" isn't just locked -- it's not
-- physically THERE at all (GPURackDisplay.client.lua hides its whole
-- shell) -- so it's skipped here too, the same way an out-of-range rack
-- already was, instead of popping up a panel for a rack you can't see.
RunService.Heartbeat:Connect(function()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local racksOwned = LocalPlayer:GetAttribute("RacksOwned") or 1

	local closestIndex, closestDist = nil, PROXIMITY_RADIUS
	if root then
		for i, p in panels do
			if i <= racksOwned then
				local dist = (root.Position - p.rackPart.Position).Magnitude
				if dist <= closestDist then
					closestDist = dist
					closestIndex = i
				end
			end
		end
	end

	for i, p in panels do
		local shouldShow = (i == closestIndex)
		if shouldShow ~= p.screen.Enabled then
			p.screen.Enabled = shouldShow
			if shouldShow then
				p.refresh()
			end
		end
	end
end)
