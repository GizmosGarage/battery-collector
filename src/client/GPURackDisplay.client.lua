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
	stay flush with the back of whichever ROW this player's owned racks
	currently reach, instead of always covering the whole column's depth
	even when only the front row (or less) is actually built.

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
-- hidden entirely instead of just showing 4 empty slots.
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
-- enough for that WHOLE column (every row GPUs.floorTiers[1].maxRacks
-- covers), but a player who's only bought a few racks into it shouldn't
-- see empty floor stretching out past them -- resize/reposition it
-- (client-side, same trick as the racks above) to stay flush with the
-- back of whichever row their OWNED racks in column 1 currently reach.
local platform = workspace.DataCenter:WaitForChild("Platform")
local platformFrontEdge = platform.Position.Z - platform.Size.Z / 2
local platformX, platformY, platformWidth, platformHeight =
	platform.Position.X, platform.Position.Y, platform.Size.X, platform.Size.Y
local COLUMN_1_MAX_RACKS = GPUs.floorTiers[1].maxRacks

local function updatePlatformDepth(racksOwned)
	local reachedIndex = math.max(1, math.min(racksOwned, COLUMN_1_MAX_RACKS, #racks))
	local reachedRack = racks[reachedIndex]
	local backEdge = reachedRack.Position.Z + reachedRack.Size.Z / 2
	local depth = backEdge - platformFrontEdge
	platform.Size = Vector3.new(platformWidth, platformHeight, depth)
	platform.CFrame = CFrame.new(platformX, platformY, platformFrontEdge + depth / 2)
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
	updatePlatformDepth(racksOwned)
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
for i in slotModels do
	LocalPlayer:GetAttributeChangedSignal("Slot" .. i .. "GPU"):Connect(render)
end
render()
