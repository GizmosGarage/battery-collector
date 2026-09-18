--[[
	GPURackDisplay  --  LocalScript
	Location: StarterPlayer > StarterPlayerScripts

	Shows/hides the GPU-card models physically built into each Server_Rack
	in Workspace, to match THIS PLAYER's own equipped rig -- the same
	per-client trick DataCenterDisplay.client.lua and
	FieldLockDisplay.client.lua use for the Data Center's ONLINE glow and a
	locked field's dimming: these are shared world Models, but a LocalScript
	changing a BasePart's properties only affects what WE see, never what
	anyone else does or what's actually saved.

	Each Server_Rack holds exactly 4 GPU-card models, named (bottom to top)
	GPU_Bottom, GPU_Bottom_Middle, GPU_Top_Middle, GPU_Top, nested as ITS
	OWN children -- so several racks can each have their own set under the
	same 4 names. Racks themselves are read straight out of Workspace
	(every BasePart named "Server_Rack") and put in GPUs.sortRacks order --
	column first (left to right), then row within a column (front to
	back) -- so slot 1 is always the bottom card of column 1's frontmost
	rack, slot 5 is the bottom card of the rack right behind it, and so on.
	Add another rack in Studio later (same naming) and this script picks
	it up with no code change -- the same live-reads-the-world habit
	Fields.lua uses for Pad sizes instead of hard-coding them.

	Slot N is shown exactly when this player's "Slot<N>GPU" attribute
	(published by Shop.server.lua) is non-empty -- a LOCKED slot (past
	however many this player has actually unlocked) publishes "" too, same
	as an unlocked-but-empty one, so it's already handled the same way --
	no GPUs equipped anywhere shows a completely empty rack.

	The RACK SHELL itself (the MeshPart plus its 4 side panels) is a
	SEPARATE, coarser check: rack N is only shown at all once this
	player's "RacksOwned" attribute is at least N -- a rack they haven't
	bought yet doesn't physically exist for them, not even as an empty
	shell. Slots inside an unowned rack are moot (never unlocked, so
	always hidden anyway), but hiding the shell too is what actually
	makes an unbought rack disappear instead of standing there empty.

	The FLOOR under column 1 (Workspace.DataCenter.Platform) gets the
	same treatment, one level coarser still: it's resized/repositioned to
	stay flush with the back of whichever ROW this player's FLOOR TIER
	has room for (not how many of those racks are actually bought yet) --
	so upgrading the floor shows the new space immediately, empty and
	waiting, instead of the floor creeping out one row at a time as racks
	get bought into it.

	Once a player's floor tier has room for the WHOLE of column 1 --
	but ONLY column 1 (tier 2, GPUs.floorTiers[2]) -- column 1's racks --
	all 16 of them, including the 4 free Starter Row ones already bought
	-- nudge sideways into two side-by-side columns, flush with the
	left/right edges of the floor tile, with a walkway down the middle,
	instead of staying one dense block. From tier 3 on (2+ WHOLE columns
	unlocked), that within-column split goes away again -- column 1 sits
	back in its one true built row, now as a whole solid aisle alongside
	column 2 (also solid, never split), with the walkway living BETWEEN
	the two columns instead of down the middle of column 1 alone. Same
	client-only trick either way: a rack's TRUE built position in Studio
	never changes, only what THIS player's client draws it at -- and this
	script only ever moves the RACK part itself. Every shell panel and
	GPU-card part is WELDED (in Studio, not in this script) directly to
	its own rack and unanchored, so it rides along automatically whenever
	the rack's CFrame changes -- a GPU card is physically incapable of
	ending up on a DIFFERENT rack than the one it's welded to, which is
	what makes this safe to nudge around at all.

	The floor itself WIDENS once 2+ columns are unlocked, but only ever
	from its RIGHT edge -- the LEFT edge (column 1's side) never moves
	from its original built position, so the room a player already knows
	from tiers 1-2 stays exactly where it was; the walkway just opens up
	further into the middle of a wider floor instead of the whole floor
	recentering around it -- see updatePlatform below. The battery
	dump-off Pad and its Sign move independently of the floor's own
	shape, staying centered on the WALKWAY itself -- but unlike
	everything else in this file, that's NOT a purely cosmetic illusion:
	DataCenter.server.lua computes that exact same X, per player, to
	know where THEIR deposit trigger actually is (see
	GPUs.dataCenterCenterX).

	WHICH GPU type is installed does matter for one thing: each card's
	FrontPanel -- the bracket the DVI-D/DisplayPort/HDMI ports sit in --
	gets painted that GPU's own color (GPUs.lua's catalog), so a glance at
	a rack shows which tier sits in each slot without opening its panel.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GPUs = require(ReplicatedStorage:WaitForChild("GPUs"))

local LocalPlayer = Players.LocalPlayer

local GPU_MODEL_NAMES = { "GPU_Bottom", "GPU_Bottom_Middle", "GPU_Top_Middle", "GPU_Top" }

-- Every Server_Rack in the world, in GPUs.sortRacks order -- see header
-- comment. GPUs.getAllRacks waits for the full count to actually exist on
-- this client (Workspace content streams in separately from this script,
-- same reason DataCenter.server.lua waits for Workspace.DataCenter
-- instead of assuming it's already there the instant this script starts
-- running) instead of scanning once and possibly missing stragglers.
local racks = GPUs.getAllRacks()

-- Flatten into one ordered list of GPU-card MODELS, slot 1 first -- rack
-- 1's four cards, then rack 2's four, and so on. A rack missing one of the
-- four names (still being built in Studio) just contributes fewer slots
-- instead of erroring.
local slotModels = {}
for _, rack in racks do
	for _, name in GPU_MODEL_NAMES do
		local model = rack:FindFirstChild(name)
		if model then
			table.insert(slotModels, model)
		end
	end
end

-- Cache each slot's visible pieces once, together with the look they
-- should have WHEN SHOWN (their normal, as-built Transparency/CanCollide)
-- -- so every later refresh is just flipping between "as built" and
-- "hidden," never re-scanning the model. TWO kinds of thing need hiding,
-- not just one: the BaseParts themselves (the card body, fan, port
-- connectors), AND any Decal/Texture stuck to one of those parts' faces
-- (the circuit-board graphic on the card) -- a Decal has its OWN
-- Transparency, completely separate from its part's, so making the part
-- invisible alone leaves its decal floating there fully visible. Only
-- BaseParts have CanCollide, so `canCollide` stays nil for a Decal/Texture
-- entry -- setSlotVisible below skips that property for those.
local slotParts = {}
local frontPanels = {}   -- i -> that slot's FrontPanel BasePart, for the color-by-GPU-type below
for i, model in slotModels do
	local parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(parts, {
				part = part,
				transparency = part.Transparency,
				canCollide = part.CanCollide,
			})
		elseif part:IsA("Decal") or part:IsA("Texture") then
			table.insert(parts, {
				part = part,
				transparency = part.Transparency,
			})
		end
	end
	slotParts[i] = parts
	frontPanels[i] = model:FindFirstChild("FrontPanel")
end

-- Hidden = fully invisible AND non-solid (so an empty slot's card can't be
-- bumped into as an invisible wall); shown = exactly what it looked like
-- as built.
local function setSlotVisible(i, visible)
	for _, entry in slotParts[i] do
		entry.part.Transparency = visible and entry.transparency or 1
		if entry.canCollide ~= nil then
			entry.part.CanCollide = visible and entry.canCollide or false
		end
	end
end

-- Cache each RACK's own shell pieces (the MeshPart itself plus its 4 side
-- panels -- NOT the GPU_* card models above, which are handled
-- separately) the same "as built" way, so a not-yet-bought rack can be
-- hidden entirely instead of just showing 4 empty slots. Only
-- Transparency/CanCollide are cached here -- POSITION doesn't need
-- tracking, since every shell panel is welded (in Studio) directly to
-- its own rack part and rides along automatically when the rack moves.
local SHELL_PART_NAMES = { "Panel_Back", "Panel_Left", "Panel_Right", "Panel_Top" }
local rackShellParts = {}
for rackIndex, rack in racks do
	local parts = { { part = rack, transparency = rack.Transparency, canCollide = rack.CanCollide } }
	for _, name in SHELL_PART_NAMES do
		local part = rack:FindFirstChild(name)
		if part then
			table.insert(parts, { part = part, transparency = part.Transparency, canCollide = part.CanCollide })
		end
	end
	rackShellParts[rackIndex] = parts
end

local function setRackVisible(rackIndex, visible)
	for _, entry in rackShellParts[rackIndex] do
		entry.part.Transparency = visible and entry.transparency or 1
		entry.part.CanCollide = visible and entry.canCollide or false
	end
end

-- The floor under column 1 (Workspace.DataCenter.Platform) is built deep
-- enough for that WHOLE column (GPUs.RACKS_PER_COLUMN), but a player
-- whose FLOOR doesn't have room for a row yet shouldn't see empty floor
-- stretching out past it -- resize/reposition it (client-side, same
-- trick as the racks above) to stay flush with the back of whichever row
-- their FLOOR TIER has room for. Deliberately keyed to the floor tier,
-- not to how many of those racks are actually bought -- upgrading the
-- floor should show the new room immediately, empty and waiting, not
-- creep out one row at a time as racks get bought into it after.
local platform = workspace.DataCenter:WaitForChild("Platform")
local platformFrontEdge = platform.Position.Z - platform.Size.Z / 2
local platformX, platformY, platformWidth, platformHeight =
	platform.Position.X, platform.Position.Y, platform.Size.X, platform.Size.Y
local platformLeftEdge = platformX - platformWidth / 2
local COLUMN_1_MAX_RACKS = math.min(GPUs.RACKS_PER_COLUMN, #racks)

-- How far the floor's BUILT right edge sits past column 1's own right
-- edge -- the same breathing room the floor already gives column 1 on
-- its (fixed) left side, reused so the floor's right edge -- the only
-- one that ever moves -- keeps that same look as it extends to cover
-- more columns, instead of going edge-tight while the left side still
-- has room to spare. Computed once, here, from column 1's TRUE built
-- position (racks[4], row 1's rightmost -- every row shares the same X)
-- -- this runs before render() ever applies the tier-2 split, so it's
-- never at risk of measuring a shifted rack by mistake.
local PLATFORM_RIGHT_MARGIN = (platformX + platformWidth / 2) - (racks[4].Position.X + racks[4].Size.X / 2)

-- The battery dump-off Pad and its floating Sign move independently of
-- the floor's own shape -- centered on the WALKWAY itself (see
-- GPUs.dataCenterCenterX), not the floor's own midpoint, since the
-- floor's left edge below deliberately stops recentering. This has to
-- stay a SHARED formula with DataCenter.server.lua, not just local math
-- here -- see GPUs.dataCenterCenterX for why.
local pad = workspace.DataCenter:WaitForChild("Pad")
local sign = workspace.DataCenter:FindFirstChild("Sign")
local padY, padZ = pad.Position.Y, pad.Position.Z
local signY, signZ = sign and sign.Position.Y, sign and sign.Position.Z

-- DEPTH always stays keyed to column 1's own rows (every column shares
-- the same 4 row positions, so this never needs to change once a WHOLE
-- column's worth of depth is reached). The LEFT edge never moves --
-- always the floor's own BUILT left edge, flush with column 1's side,
-- exactly where a player already knows it from tiers 1-2 -- only the
-- RIGHT edge extends outward once 2+ whole columns are unlocked, to
-- stay flush (plus the same margin column 1 already gets) with the
-- rightmost RACK actually in play. That's what opens the walkway up in
-- the MIDDLE of the floor instead of the whole floor recentering around
-- it every time a new column unlocks.
local function updatePlatform(floorTier)
	local capacity = GPUs.maxRacksForTier(floorTier) or 1
	local columnsCovered = capacity // GPUs.RACKS_PER_COLUMN

	local reachedIndex = math.max(1, math.min(capacity, COLUMN_1_MAX_RACKS))
	local reachedRack = racks[reachedIndex]
	local backEdge = reachedRack.Position.Z + reachedRack.Size.Z / 2
	local depth = backEdge - platformFrontEdge

	local rightEdge = platformX + platformWidth / 2
	if columnsCovered >= 2 then
		local rightRackIndex = math.min((columnsCovered - 1) * GPUs.RACKS_PER_COLUMN + 4, #racks)
		local rightRack = racks[rightRackIndex]
		rightEdge = (rightRack.Position.X + rightRack.Size.X / 2) + PLATFORM_RIGHT_MARGIN
	end
	local width = rightEdge - platformLeftEdge
	local centerX = (platformLeftEdge + rightEdge) / 2

	platform.Size = Vector3.new(width, platformHeight, depth)
	platform.CFrame = CFrame.new(centerX, platformY, platformFrontEdge + depth / 2)

	local padCenterX = GPUs.dataCenterCenterX(floorTier, racks)
	pad.CFrame = CFrame.new(padCenterX, padY, padZ)
	if sign then
		sign.CFrame = CFrame.new(padCenterX, signY, signZ)
	end
end

-- ---------- tier-2-ONLY split layout for column 1 ----------
-- While exactly one whole column is unlocked (tier 2, GPUs.floorTiers[2]
-- -- see the columnsCovered check in render() below), column 1's racks
-- split apart into two side-by-side columns, flush with the platform's
-- own left and right edges, with a walkway down the middle -- instead of
-- sitting in one dense block with empty floor stretching out to one
-- side. From tier 3 on, applyColumn1Split gets called with
-- splitActive=false instead, putting column 1 right back in its one
-- true built row. Column 1's racks, grouped into physical ROWS --
-- consecutive racks sharing the same Z, since GPUs.sortRacks already
-- puts them in row order front-to-back -- reads the actual built spacing
-- instead of hard-coding "4 racks per row," the same "detect it, don't
-- hard-code it" habit GPUs.sortRacks itself uses for column boundaries.
--
-- Only the RACK part itself gets moved here -- every shell panel and
-- GPU-card part is welded (in Studio) directly to its own rack and
-- unanchored, so the whole assembly rides along automatically. That's
-- also what makes a GPU card structurally incapable of ending up on the
-- wrong rack: it's not "the script remembered to move it," it's
-- physically attached to one specific rack and nothing else.
local function groupIntoRows(rackIndices)
	local rows = {}
	local currentRow
	for _, rackIndex in rackIndices do
		local z = racks[rackIndex].Position.Z
		if not currentRow or z ~= racks[currentRow[1]].Position.Z then
			currentRow = {}
			table.insert(rows, currentRow)
		end
		table.insert(currentRow, rackIndex)
	end
	return rows
end

local column1Indices = {}
for i = 1, COLUMN_1_MAX_RACKS do
	column1Indices[i] = i
end
local column1Rows = groupIntoRows(column1Indices)

-- How wide a gap to open down the middle -- picked so each half ends up
-- FLUSH with the platform's own left/right edge: the walkway is
-- whatever's left over after the row's own built width (leftmost rack's
-- left edge to rightmost rack's right edge) is subtracted from the
-- platform's full width, split evenly so both edges land flush at once.
local WALKWAY_WIDTH = 0
do
	local firstRow = column1Rows[1]
	if firstRow and #firstRow > 0 then
		local leftmostRack = racks[firstRow[1]]
		local rightmostRack = racks[firstRow[#firstRow]]
		local rowSpan = (rightmostRack.Position.X + rightmostRack.Size.X / 2)
			- (leftmostRack.Position.X - leftmostRack.Size.X / 2)
		WALKWAY_WIDTH = math.max(0, platformWidth - rowSpan)
	end
end

-- rackIndex -> the sideways Vector3 nudge that rack needs for the split
-- layout -- the first half of each row (smaller X, the left side) nudges
-- left, the second half nudges right, so a row of racks that used to
-- touch in a single line now sits as two even pairs flush with the
-- platform's edges, with a walkway between them.
local splitOffset = {}
for _, row in column1Rows do
	local half = #row / 2
	for position, rackIndex in row do
		local side = position <= half and -1 or 1
		splitOffset[rackIndex] = Vector3.new(side * WALKWAY_WIDTH / 2, 0, 0)
	end
end

-- Column 1's racks, cached with their TRUE built CFrame (the split
-- OFF position) -- every later call computes "original spot plus a
-- sideways nudge" from this fixed baseline, instead of repeated calls
-- (floor tier going up, or a fresh player joining already past tier 2)
-- drifting further from the true built position.
local column1OriginalCFrame = {}
for rackIndex = 1, COLUMN_1_MAX_RACKS do
	column1OriginalCFrame[rackIndex] = racks[rackIndex].CFrame
end

local function applyColumn1Split(splitActive)
	for rackIndex = 1, COLUMN_1_MAX_RACKS do
		local offset = splitActive and splitOffset[rackIndex] or Vector3.zero
		racks[rackIndex].CFrame = column1OriginalCFrame[rackIndex] + offset
	end
end

-- Everything starts hidden -- an empty world until we actually know
-- otherwise (render(), below, runs immediately after this).
for rackIndex in racks do
	setRackVisible(rackIndex, false)
end
for i in slotModels do
	setSlotVisible(i, false)
end

local function render()
	local racksOwned = LocalPlayer:GetAttribute("RacksOwned") or 1
	local floorTier = LocalPlayer:GetAttribute("FloorTier") or 1
	-- Split ONLY while exactly one whole column is unlocked (tier 2) --
	-- from tier 3 on (2+ columns), column 1 sits back in its single true
	-- built row, now a whole aisle alongside column 2 instead of split
	-- into two halves of itself. See the header comment for why.
	local columnsCovered = (GPUs.maxRacksForTier(floorTier) or 0) // GPUs.RACKS_PER_COLUMN
	local splitActive = columnsCovered == 1

	applyColumn1Split(splitActive)
	updatePlatform(floorTier)
	for rackIndex in racks do
		setRackVisible(rackIndex, rackIndex <= racksOwned)
	end

	for i in slotModels do
		local gpuId = LocalPlayer:GetAttribute("Slot" .. i .. "GPU")
		local filled = gpuId ~= nil and gpuId ~= ""
		setSlotVisible(i, filled)

		local gpu = filled and GPUs.get(gpuId)
		if gpu and frontPanels[i] then
			frontPanels[i].Color = gpu.color
		end
	end
end

LocalPlayer:GetAttributeChangedSignal("RacksOwned"):Connect(render)
LocalPlayer:GetAttributeChangedSignal("FloorTier"):Connect(render)
for i in slotModels do
	LocalPlayer:GetAttributeChangedSignal("Slot" .. i .. "GPU"):Connect(render)
end
render()
