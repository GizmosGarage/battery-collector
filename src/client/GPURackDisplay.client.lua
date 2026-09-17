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

-- The racks (and their GPU cards) are Workspace content that streams in
-- separately from this script -- wait for at least the first one to exist
-- before scanning, same reason DataCenter.server.lua waits for
-- Workspace.DataCenter instead of assuming it's already there the instant
-- this script starts running.
workspace:WaitForChild("Server_Rack", 10)

-- Every Server_Rack in the world, in GPUs.sortRacks order -- see header
-- comment.
local unsortedRacks = {}
for _, child in workspace:GetChildren() do
	if child.Name == "Server_Rack" and child:IsA("BasePart") then
		table.insert(unsortedRacks, child)
	end
end
local racks = GPUs.sortRacks(unsortedRacks)

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

-- Every card starts hidden -- an empty rack until we actually know
-- otherwise (render(), below, runs immediately after this).
for i in slotModels do
	setSlotVisible(i, false)
end

local function render()
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

for i in slotModels do
	LocalPlayer:GetAttributeChangedSignal("Slot" .. i .. "GPU"):Connect(render)
end
render()
