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

	Tier 1 never moves column 1 at all -- it shows row 1 alone (4 racks)
	exactly the way it was built. Tiers 2-3 (8 and 16 racks,
	GPUs.floorTiers[2..3]) are the odd ones out: rather than stacking
	rows front-to-back the way they were actually built (16 studs apart
	in Z), every row moves sideways onto one of exactly 2 SIDES (odd rows
	left, even rows right) -- so tier 2's 2 rows read as two side-by-side
	blocks, one row deep each, a walkway between them, both equally close
	to the player. Tier 3's extra 2 rows go BEHIND those same two blocks
	(one ROW_SPACING further back, on their own matching side) rather
	than opening a third or fourth block -- so tier 3 looks like tier 2's
	same two aisles, just 2 rows deep now instead of 1 (see
	computeRowOffsets and ROW_SPLIT_SIDES). Both sides shift an EQUAL
	distance from their shared natural center (ROW_CENTER_X), which is
	what keeps the dump-off Pad (see below) landing on the correct X
	without needing to know anything about this split -- the same shared
	formula that works for every other tier still works here.

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
	from tier 1 stays exactly where it was; the walkway just opens up
	further into the middle of a wider floor instead of the whole floor
	recentering around it -- see updatePlatform below. Tiers 2-3 are the
	exception that DOES recenter: since their row-split sides spread out
	evenly from their shared natural center rather than flushing one
	fixed edge, the floor grows from BOTH sides at once, centered on that
	same point -- tier 3 just needs a DEEPER floor than tier 2 to fit its
	extra row per side, not a wider one (same width, both tiers).
	The battery dump-off Pad and its Sign move independently of the
	floor's own shape, staying centered on the WALKWAY itself -- but
	unlike everything else in this file, that's NOT a purely cosmetic
	illusion: DataCenter.server.lua computes that exact same X, per
	player, to know where THEIR deposit trigger actually is (see
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

-- How many racks make up ONE built ROW (front-to-back position) within a
-- column -- 4, touching, same as SLOTS_PER_RACK's 4 but a genuinely
-- different physical fact (one's "GPU slots per rack," this is "racks
-- across per row") that only coincidentally shares the number.
local RACKS_PER_ROW = 4

-- Row 1's own TRUE built width and center -- EVERY row in EVERY column
-- shares this exact width and X-range (rows only differ in Z, never X),
-- so "row 1's own edges" doubles as "any row's own edges." Reused below
-- for the row-split layout, which needs to know how wide ONE row is and
-- where its natural (unmoved) center sits.
local ROW_WIDTH = trueColRight[1] - trueColLeft[1]
local ROW_CENTER_X = (trueColLeft[1] + trueColRight[1]) / 2

-- How far apart (in Z) two CONSECUTIVE built rows sit -- row 2's own true
-- Z minus row 1's, read from the world rather than hard-coded (same "read
-- it, don't assume it" habit as everything else measured off
-- originalCFrame in this file). Reused below to stack rows BEHIND each
-- other within one side of the row-split layout.
local ROW_SPACING = originalCFrame[RACKS_PER_ROW + 1].Position.Z - originalCFrame[1].Position.Z

-- Tiers 2-3 ONLY: how wide a walkway to leave between the two SIDE-BY-SIDE
-- groups of rows -- reusing WIDEST_NATURAL_GAP (rather than inventing a
-- new number) just for a consistent "how wide is a walkway in this game"
-- feel with the column split further down.
local ROW_SPLIT_WALKWAY = WIDEST_NATURAL_GAP

-- The row-split layout always uses exactly 2 side-by-side groups (left
-- and right) -- what changes tier to tier is how many rows DEEP each
-- side goes, not how many sides there are. Tier 2 (8 racks) is 2 sides,
-- 1 row deep each; tier 3 (16 racks, the whole column) is the SAME 2
-- sides, just 2 rows deep each -- the two rows tier 3 adds go BEHIND the
-- two tier 2 already shows, not beside them.
local ROW_SPLIT_SIDES = 2

-- True for exactly the capacities that need MORE than one of column 1's
-- built rows -- today that's tiers 2 and 3 (8 and 16 racks). Tier 1 (4
-- racks, a single row) falls outside this range and keeps its simpler,
-- unmoved treatment.
local function isRowSplitCapacity(capacity)
	return capacity > RACKS_PER_ROW and capacity <= GPUs.RACKS_PER_COLUMN
end

-- side (1 or 2) -> the X offset to apply to every row on THAT side, for
-- any row-split capacity. Always spaces the SAME 2 groups side by side,
-- centered on ROW_CENTER_X -- row 1's own natural center, which every
-- row already shares -- rather than flush to the floor's fixed left edge
-- the way columns are (see computeColumnOffsets). That centering is
-- deliberate, not just simpler: it's what lets GPUs.dataCenterCenterX
-- (the pad's shared formula) land on the exact same X whether it reads
-- these racks' TRUE positions (as the SERVER always does) or their
-- shifted ones (as the client does after applyColumnLayout runs) --
-- shifting every side an EQUAL distance from the SAME natural center
-- can't change that center, no matter how far the shift is, which is not
-- true of a flush-to-one-fixed-edge shift. Doesn't depend on how many
-- rows deep each side goes -- that's depth (Z), a separate concern
-- handled in applyColumnLayout -- only which 2 X's the sides sit at.
-- Returns an empty table when `capacity` isn't a row-split capacity, so
-- callers can treat "no entry for side 1" as "nothing to do here."
local function computeRowOffsets(capacity)
	local offset = {}
	if not isRowSplitCapacity(capacity) then
		return offset
	end

	local totalWidth = ROW_SPLIT_SIDES * ROW_WIDTH + (ROW_SPLIT_SIDES - 1) * ROW_SPLIT_WALKWAY
	local liveLeft = ROW_CENTER_X - totalWidth / 2
	for side = 1, ROW_SPLIT_SIDES do
		offset[side] = liveLeft - trueColLeft[1]
		liveLeft = liveLeft + ROW_WIDTH + ROW_SPLIT_WALKWAY
	end
	return offset
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
-- column's worth of depth is reached) -- reads Z live off `racks` for
-- the non-row-split tiers, which is fine, since nothing touches a
-- rack's Z there. A row-split capacity (tiers 2-3) instead computes
-- depth ANALYTICALLY, from row 1's TRUE Z plus however many ROW_SPACINGs
-- deep that side goes (see ROW_SPLIT_SIDES) -- it can't just read a
-- rack's live Z the way the others do, because applyColumnLayout may
-- have already collapsed that exact rack onto a DIFFERENT depth by the
-- time this runs. The LEFT edge stays at the floor's own BUILT position
-- for tier 1 and every tier from 4 on (flush with column 1's side,
-- exactly where a player already knows it) -- a row-split capacity is
-- the one exception, widening (and RECENTERING -- see computeRowOffsets
-- for why centering, not flushing one edge, is what keeps the pad
-- formula safe here) around ROW_CENTER_X instead of anywhere near the
-- floor's fixed left edge. From tier 4 on, only the RIGHT edge extends
-- outward, to stay flush with wherever computeColumnOffsets puts the
-- last covered column's right edge -- reads TRUE positions plus that
-- SAME offset table, never live off `racks` -- applyColumnLayout may
-- have already moved that column by the time this runs (see render()),
-- and measuring its already-shifted position here would double-count
-- the offset. That's what opens the walkway up in the MIDDLE of the
-- floor instead of the whole floor recentering around it every time a
-- new column unlocks.
local function updatePlatform(floorTier)
	local capacity = GPUs.maxRacksForTier(floorTier) or 1
	local columnsCovered = capacity // GPUs.RACKS_PER_COLUMN
	local rowSplit = isRowSplitCapacity(capacity)

	local depth
	if rowSplit then
		local rowsPerSide = capacity // (RACKS_PER_ROW * ROW_SPLIT_SIDES)
		local backEdge = originalCFrame[1].Position.Z + (rowsPerSide - 1) * ROW_SPACING + racks[1].Size.Z / 2
		depth = backEdge - platformFrontEdge
	else
		local reachedIndex = math.max(1, math.min(capacity, COLUMN_1_MAX_RACKS))
		local reachedRack = racks[reachedIndex]
		local backEdge = reachedRack.Position.Z + reachedRack.Size.Z / 2
		depth = backEdge - platformFrontEdge
	end

	local leftEdge = platformLeftEdge
	local rightEdge = platformX + platformWidth / 2
	if rowSplit then
		local totalWidth = ROW_SPLIT_SIDES * ROW_WIDTH + (ROW_SPLIT_SIDES - 1) * ROW_SPLIT_WALKWAY
		leftEdge = ROW_CENTER_X - totalWidth / 2
		rightEdge = ROW_CENTER_X + totalWidth / 2
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
-- Column 1 gets one of three treatments. Tier 1 (a single row) leaves it
-- at its one true built position -- no offset at all. Tiers 2-3 (a
-- row-split capacity -- see computeRowOffsets) are the odd ones out:
-- instead of stacking rows front-to-back the way they were built, each
-- BUILT row moves sideways onto whichever of the 2 sides it belongs to
-- (odd rows left, even rows right) AND forward/back onto that SIDE's own
-- stack of depths, starting from row 1's Z and going back one
-- ROW_SPACING per extra row on that side -- so tier 2's 2 rows read as
-- two side-by-side blocks 1 row deep, and tier 3's 4 rows read as those
-- SAME two blocks, now 2 rows deep -- the 2 rows tier 3 adds go BEHIND
-- the 2 tier 2 already shows, not beside them. Tier 4+ (2+ columns)
-- shifts column 1 flush with the FLOOR's own fixed left edge (see
-- computeColumnOffsets) -- a completely different, one-sided kind of
-- widening than the row-split's centered one, since by then the floor's
-- LEFT edge has already been claimed as "the one thing that never moves"
-- (see updatePlatform).
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
	local rowOffsetX = computeRowOffsets(capacity)

	if next(rowOffsetX) then
		local totalRows = capacity // RACKS_PER_ROW
		local baseZ = originalCFrame[1].Position.Z
		for row = 1, totalRows do
			local side = (row - 1) % ROW_SPLIT_SIDES + 1
			local depthSlot = (row - 1) // ROW_SPLIT_SIDES
			local targetZ = baseZ + depthSlot * ROW_SPACING
			local firstRack = (row - 1) * RACKS_PER_ROW + 1
			local deltaZ = targetZ - originalCFrame[firstRack].Position.Z
			for rackIndex = firstRack, firstRack + RACKS_PER_ROW - 1 do
				racks[rackIndex].CFrame = originalCFrame[rackIndex] + Vector3.new(rowOffsetX[side], 0, deltaZ)
			end
		end
		-- Any of column 1's racks beyond what this capacity reveals stay
		-- hidden (render()'s setRackVisible), so their position doesn't
		-- matter to a player -- put them back at their built spot anyway,
		-- just so nothing is left sitting at a stale CFrame from a
		-- PREVIOUS tier's row-split math.
		for rackIndex = totalRows * RACKS_PER_ROW + 1, COLUMN_1_MAX_RACKS do
			racks[rackIndex].CFrame = originalCFrame[rackIndex]
		end
	else
		for rackIndex = 1, COLUMN_1_MAX_RACKS do
			racks[rackIndex].CFrame = originalCFrame[rackIndex] + Vector3.new(columnOffset[1] or 0, 0, 0)
		end
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
