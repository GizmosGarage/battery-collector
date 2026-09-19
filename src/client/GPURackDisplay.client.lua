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

	Tiers 1-3 (GPUs.floorTiers[1..3]) never move column 1 at all -- each
	one just reveals MORE of that one true built row/column, lined up
	exactly the way it was always built: tier 1 shows row 1 (4 racks),
	tier 2 shows rows 1-2 (8 racks, divided from each other by nothing
	more than the row spacing already built into the world -- see
	COLUMN_1_MAX_RACKS/the row math in updatePlatform), and tier 3 shows
	the WHOLE column (all 16 racks, rows 1-4) -- never split into two
	aisles the way an earlier version of this file tried and reverted.

	From tier 4 on (2+ WHOLE columns unlocked), column 1 moves for the
	first time -- now as a whole solid aisle alongside column 2 (also
	solid) -- but the two columns don't just sit at their closer, natural
	spacing: column 1 flushes LEFT against the floor's own fixed left
	edge, and column 2 flushes RIGHT against the floor's own (extended)
	right edge, widening the walkway between them to fill however much
	room the floor actually has.

	Tier 5 (all 4 columns, GPUs.floorTiers[5]) goes further still: rather
	than only the OUTER two columns (1 and 4) moving while 2 and 3 sit at
	their closer, natural built spacing, EVERY column from 2 on gets
	spaced the SAME distance from its neighbor (the widest gap any two
	columns were already built with -- see WIDEST_NATURAL_GAP) -- so
	every walkway between every pair of columns ends up equally wide,
	instead of the two middle columns sitting oddly close together
	between two much wider outer walkways. With 4 equal-width columns
	evenly spaced like that, the dump-off Pad (see below) naturally lands
	exactly between columns 2 and 3 -- the true middle of the whole row --
	without needing any separate "center the pad" logic of its own.

	Same client-only trick every tier: a rack's TRUE built position in
	Studio never changes, only what THIS player's client draws it at --
	and this script only ever moves the RACK part itself. Every shell
	panel and GPU-card part is WELDED (in Studio, not in this script)
	directly to its own rack and unanchored, so it rides along
	automatically whenever the rack's CFrame changes -- a GPU card is
	physically incapable of ending up on a DIFFERENT rack than the one
	it's welded to, which is what makes this safe to nudge around at all.

	The floor itself WIDENS once 2+ columns are unlocked, but only ever
	from its RIGHT edge -- the LEFT edge (column 1's side) never moves
	from its original built position, so the room a player already knows
	from tiers 1-3 stays exactly where it was; the walkway just opens up
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

-- EVERY rack's TRUE built CFrame, captured right away, before anything
-- else in this script ever has a chance to nudge one sideways. Every
-- later "where should this rack sit" calculation (the tier-4+ column
-- flush and the floor's own right-edge math) reads POSITIONS from here,
-- never live off `racks[i].Position` -- a rack that's already been
-- nudged this render() would otherwise get double-counted by whichever
-- calculation runs after it moved.
local originalCFrame = {}
for i = 1, #racks do
	originalCFrame[i] = racks[i].CFrame
end

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
local TOTAL_COLUMNS = GPUs.MAX_RACKS // GPUs.RACKS_PER_COLUMN

-- Column c's TRUE built left/right edge (that column's front row, leftmost
-- rack's left edge to rightmost rack's right edge) -- read once from
-- originalCFrame, the same "read the world instead of hard-coding it"
-- habit GPUs.sortRacks already uses for column boundaries. Every column
-- shares the same width (they're identical rows of touching racks), so
-- this is really just "where does column c happen to sit," reusable by
-- both the margin below and the tier-5 equal-gap spacing further down.
local trueColLeft, trueColRight = {}, {}
for c = 1, TOTAL_COLUMNS do
	local firstRack = (c - 1) * GPUs.RACKS_PER_COLUMN + 1
	local lastFrontRowRack = firstRack + 3
	trueColLeft[c] = originalCFrame[firstRack].Position.X - racks[firstRack].Size.X / 2
	trueColRight[c] = originalCFrame[lastFrontRowRack].Position.X + racks[lastFrontRowRack].Size.X / 2
end

-- How far the floor's BUILT right edge sits past column 1's own right
-- edge -- the same breathing room the floor already gives column 1 on
-- its (fixed) left side, reused below: how far the floor's own right
-- edge extends past whichever column is last covered (2 columns only --
-- see WIDEST_NATURAL_GAP for 3+), AND how far that column has to shift
-- right (and column 1 left) to land flush with the floor's edges -- see
-- computeColumnOffsets.
local PLATFORM_RIGHT_MARGIN = (platformX + platformWidth / 2) - trueColRight[1]

-- Tier 5 ONLY (3+ whole columns covered): the widest gap BETWEEN any two
-- ADJACENT columns, as they were actually built -- column 1 and 2 were
-- built closer together than columns 2-3 and 3-4 (see the README). Using
-- this as the SAME gap between every covered column (computeColumnOffsets
-- below), instead of each pair's own narrower built gap, means no pair
-- ends up closer than any other, and no gap ever has to shrink to become
-- equal -- the floor only ever grows to fit the widest one already there.
local WIDEST_NATURAL_GAP = 0
for c = 1, TOTAL_COLUMNS - 1 do
	WIDEST_NATURAL_GAP = math.max(WIDEST_NATURAL_GAP, trueColLeft[c + 1] - trueColRight[c])
end

-- The X offset to apply to column c's TRUE built position, for c = 1
-- through however many columns are covered -- the ONE place both
-- applyColumnLayout (moves the racks) and updatePlatform (sizes the
-- floor around wherever the last covered column ends up) compute this,
-- so the two can never disagree about where a column actually sits.
--   Fewer than 2 columns covered (tiers 1-3 -- 0 columns for tiers 1-2's
--     4/8 racks, exactly 1 for tier 3's full 16): returns an empty table
--     -- no column moves; applyColumnLayout/updatePlatform each already
--     handle that case on their own.
--   Exactly 2 columns covered (tier 4): column 1 flushes LEFT and column
--     2 flushes RIGHT by PLATFORM_RIGHT_MARGIN each -- unchanged from
--     before. With only one gap total, it's already "equal to itself,"
--     nothing more to do.
--   3+ columns covered (tier 5): column 1 still flushes LEFT the same
--     way, but every column from 2 on is placed WIDEST_NATURAL_GAP past
--     the previous column's (now-shifted) right edge -- so every covered
--     column ends up the same distance from its neighbor, not just the
--     two outer ones. The last covered column's resulting right edge is
--     what the floor flushes its own right edge against.
local function computeColumnOffsets(columnsCovered)
	local offset = {}
	if columnsCovered < 2 then
		return offset
	end

	offset[1] = -PLATFORM_RIGHT_MARGIN
	if columnsCovered == 2 then
		offset[2] = PLATFORM_RIGHT_MARGIN
	else
		local liveRight = trueColRight[1] + offset[1]
		for c = 2, columnsCovered do
			local liveLeft = liveRight + WIDEST_NATURAL_GAP
			offset[c] = liveLeft - trueColLeft[c]
			liveRight = trueColRight[c] + offset[c]
		end
	end
	return offset
end

-- Tier 3 ONLY (exactly one whole column, 16 racks, revealed as a single
-- row): extra breathing room to add to EACH side of the floor, beyond
-- the built margin above -- Ethan wants that tier's clearance a little
-- more generous than tiers 1-2's without moving the racks or the
-- floor's center, so this only ever widens the floor symmetrically
-- around the row it already has (see updatePlatform). Not used for any
-- other tier -- tiers 1-2 stay exactly as built, and tier 4+ keeps its
-- own flush-to-the-last-column sizing untouched.
local COLUMN_1_EXTRA_CLEARANCE = 2

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
-- column's worth of depth is reached) -- reads Z live off `racks`, which
-- is fine, since nothing in this script ever touches a rack's Z. The
-- LEFT edge stays at the floor's own BUILT position for tiers 1-2 and
-- every tier from 4 on (flush with column 1's side, exactly where a
-- player already knows it) -- tier 3 is the one exception, nudging BOTH
-- edges outward by COLUMN_1_EXTRA_CLEARANCE (see above) for a little
-- more breathing room next to that one full column, without moving the
-- racks or recentering the floor. From tier 4 on, only the RIGHT edge
-- extends outward, to stay flush with wherever computeColumnOffsets puts
-- the last covered column's right edge -- reads TRUE positions plus that
-- SAME offset table, never live off `racks` -- applyColumnLayout may
-- have already moved that column by the time this runs (see render()),
-- and measuring its already-shifted position here would double-count
-- the offset. That's what opens the walkway up in the MIDDLE of the
-- floor instead of the whole floor recentering around it every time a
-- new column unlocks.
local function updatePlatform(floorTier)
	local capacity = GPUs.maxRacksForTier(floorTier) or 1
	local columnsCovered = capacity // GPUs.RACKS_PER_COLUMN

	local reachedIndex = math.max(1, math.min(capacity, COLUMN_1_MAX_RACKS))
	local reachedRack = racks[reachedIndex]
	local backEdge = reachedRack.Position.Z + reachedRack.Size.Z / 2
	local depth = backEdge - platformFrontEdge

	local leftEdge = platformLeftEdge
	local rightEdge = platformX + platformWidth / 2
	if columnsCovered == 1 then
		leftEdge = leftEdge - COLUMN_1_EXTRA_CLEARANCE
		rightEdge = rightEdge + COLUMN_1_EXTRA_CLEARANCE
	elseif columnsCovered >= 2 then
		local columnOffset = computeColumnOffsets(columnsCovered)
		rightEdge = trueColRight[columnsCovered] + columnOffset[columnsCovered]
	end
	local width = rightEdge - leftEdge
	local centerX = (leftEdge + rightEdge) / 2

	platform.Size = Vector3.new(width, platformHeight, depth)
	platform.CFrame = CFrame.new(centerX, platformY, platformFrontEdge + depth / 2)

	local padCenterX = GPUs.dataCenterCenterX(floorTier, racks)
	pad.CFrame = CFrame.new(padCenterX, padY, padZ)
	if sign then
		sign.CFrame = CFrame.new(padCenterX, signY, signZ)
	end
end

-- ---------- column layout, by tier ----------
-- Only the RACK part itself gets moved here -- every shell panel and
-- GPU-card part is welded (in Studio) directly to its own rack and
-- unanchored, so the whole assembly rides along automatically. That's
-- also what makes a GPU card structurally incapable of ending up on the
-- wrong rack: it's not "the script remembered to move it," it's
-- physically attached to one specific rack and nothing else.
--
-- Column 1 gets one of two treatments depending on how many whole
-- columns are unlocked: tiers 1-3 (0-1 columns -- 4, 8, or all 16 of its
-- own racks) leave it at its one true built row -- tiers 2 and 3 just
-- reveal more of that same row/column, lined up exactly like tier 1,
-- never split into two aisles; tier 4+ (2+ columns) shifts it flush with
-- the FLOOR's own fixed left edge (see computeColumnOffsets).
--
-- At exactly 2 columns (tier 4), column 2 flushes RIGHT the same way,
-- against the floor's own extended right edge, widening the one walkway
-- between them to fill however much room the floor has. At 3+ columns
-- (tier 5), EVERY column from 2 on -- not just the last one -- gets
-- spaced WIDEST_NATURAL_GAP from its neighbor, so the gaps beside
-- columns 2 and 3 are exactly as wide as the gap beside column 1 and the
-- last column, instead of columns 2-3 sitting at their narrower natural
-- spacing while only the outer walkways widen. That's also what puts the
-- dump-off pad exactly between columns 2 and 3 -- see
-- GPUs.dataCenterCenterX, which centers on column 1's left edge and the
-- last column's right edge; with every column the same width and every
-- gap the same size, that midpoint always falls in the middle of the
-- MIDDLE gap.
local function applyColumnLayout(floorTier)
	local capacity = GPUs.maxRacksForTier(floorTier) or 1
	local columnsCovered = capacity // GPUs.RACKS_PER_COLUMN
	local columnOffset = computeColumnOffsets(columnsCovered)

	for rackIndex = 1, COLUMN_1_MAX_RACKS do
		racks[rackIndex].CFrame = originalCFrame[rackIndex] + Vector3.new(columnOffset[1] or 0, 0, 0)
	end

	for columnIndex = 2, TOTAL_COLUMNS do
		local firstRack = (columnIndex - 1) * GPUs.RACKS_PER_COLUMN + 1
		local lastRack = math.min(columnIndex * GPUs.RACKS_PER_COLUMN, #racks)
		local offset = Vector3.new(columnOffset[columnIndex] or 0, 0, 0)
		for rackIndex = firstRack, lastRack do
			racks[rackIndex].CFrame = originalCFrame[rackIndex] + offset
		end
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

	applyColumnLayout(floorTier)
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
