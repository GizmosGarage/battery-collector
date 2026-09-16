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
	(every BasePart named "Server_Rack"), sorted by Z position, so slot 1
	is always the bottom card of whichever rack sits at the smallest Z,
	slot 5 is the bottom card of the next rack over, and so on. Add another
	rack in Studio later (same naming, further along +Z) and this script
	picks it up with no code change -- the same live-reads-the-world habit
	Fields.lua uses for Pad sizes instead of hard-coding them.

	Slot N is shown exactly when this player's "Slot<N>GPU" attribute
	(published by Shop.server.lua) is non-empty -- which GPU TYPE is
	installed doesn't matter, only whether the slot is filled, so a Starter
	and a Neural Accelerator look identical on the rack. A LOCKED slot (past
	however many this player has actually unlocked) publishes "" too, same
	as an unlocked-but-empty one, so it's already handled the same way --
	no GPUs equipped anywhere shows a completely empty rack.
--]]

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local GPU_MODEL_NAMES = { "GPU_Bottom", "GPU_Bottom_Middle", "GPU_Top_Middle", "GPU_Top" }

-- The racks (and their GPU cards) are Workspace content that streams in
-- separately from this script -- wait for at least the first one to exist
-- before scanning, same reason DataCenter.server.lua waits for
-- Workspace.DataCenter instead of assuming it's already there the instant
-- this script starts running.
workspace:WaitForChild("Server_Rack", 10)

-- Every Server_Rack in the world, left-to-right in build order (smallest Z
-- first -- see header comment).
local racks = {}
for _, child in workspace:GetChildren() do
	if child.Name == "Server_Rack" and child:IsA("BasePart") then
		table.insert(racks, child)
	end
end
table.sort(racks, function(a, b)
	return a.Position.Z < b.Position.Z
end)

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

-- Cache each slot's BaseParts once, together with the look they should
-- have WHEN SHOWN (their normal, as-built Transparency/CanCollide) -- so
-- every later refresh is just flipping between "as built" and "hidden,"
-- never re-scanning the model.
local slotParts = {}
for i, model in slotModels do
	local parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(parts, {
				part = part,
				transparency = part.Transparency,
				canCollide = part.CanCollide,
			})
		end
	end
	slotParts[i] = parts
end

-- Hidden = fully invisible AND non-solid (so an empty slot's card can't be
-- bumped into as an invisible wall); shown = exactly what it looked like
-- as built.
local function setSlotVisible(i, visible)
	for _, entry in slotParts[i] do
		entry.part.Transparency = visible and entry.transparency or 1
		entry.part.CanCollide = visible and entry.canCollide or false
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
		setSlotVisible(i, gpuId ~= nil and gpuId ~= "")
	end
end

for i in slotModels do
	LocalPlayer:GetAttributeChangedSignal("Slot" .. i .. "GPU"):Connect(render)
end
render()
