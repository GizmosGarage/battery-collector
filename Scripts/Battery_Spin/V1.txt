--[[
	BatterySpin  --  LocalScript
	Location: StarterPlayer > StarterPlayerScripts

	Runs on EACH player's own machine. Purely cosmetic: leans every tagged
	battery 45 deg and spins it around the vertical axis, pivoting about the
	battery's CENTRE.

	Because this runs on the client, the server sends NO movement for the
	batteries -- every player's machine draws the animation itself, for free.
	The trade-off: the server's copy of each battery (and its Hitbox) stays
	upright and still, so collection is judged by the battery's centre, not by
	the tilted, spinning picture you see.

	We move each Part directly instead of calling Model:PivotTo(). On the client,
	PivotTo() on this model only updated the model's stored pivot without moving
	the anchored parts; writing each Part.CFrame every frame is the reliable way.
--]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- ============================ CONFIG ============================
local BATTERY_TAG          = "BatteryPickup"   -- must match BatterySpawner on the server
local TILT_DEGREES         = 45                -- how far each battery leans
local SPIN_DEGREES_PER_SEC = 90                -- spin speed around the vertical axis
-- ==============================================================

-- Constant rotations, worked out once.
local TILT_CFRAME = CFrame.Angles(math.rad(TILT_DEGREES), 0, 0)
local SPIN_RADIANS_PER_SEC = math.rad(SPIN_DEGREES_PER_SEC)

-- How many BaseParts a fully-replicated battery has (terminal, top_cap,
-- upper_body, lower_body, Hitbox). We wait for all of them before caching poses.
local PART_COUNT = 5

-- battery Model -> {
--   center = Vector3,                 -- the point to pivot around
--   phase  = number (radians),        -- this battery's personal start angle
--   parts  = { [BasePart] = CFrame }, -- each part's rest pose, in the space of an
--                                        upright frame centred on `center`
-- }
local tracked = {}

-- One shared angle for every battery, so there's no per-battery float drift.
local spin = 0

-- Try to start animating a battery. Returns without recording anything if the
-- model isn't fully here yet -- the caller retries next frame.
local function track(model)
	if tracked[model] then
		return
	end

	local center = model:GetAttribute("SpawnCenter")
	if not center then
		return   -- SpawnCenter attribute hasn't replicated to us yet
	end

	-- Collect the parts. The model, its tag, its attribute and its child parts
	-- can each arrive on different frames; bail until every part is present, or
	-- we'd cache an incomplete (or empty) pose list and animate nothing.
	local partList = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(partList, part)
		end
	end
	if #partList < PART_COUNT then
		return
	end

	-- Record each part's resting pose relative to an upright frame at the centre.
	local uprightFrame = CFrame.new(center)
	local parts = {}
	for _, part in partList do
		parts[part] = uprightFrame:ToObjectSpace(part.CFrame)
	end

	tracked[model] = {
		center = center,
		phase = math.random() * 2 * math.pi,
		parts = parts,
	}
end

-- Stop animating a battery once it's collected / removed.
CollectionService:GetInstanceRemovedSignal(BATTERY_TAG):Connect(function(model)
	tracked[model] = nil
end)

-- One loop drives everything, once per frame.
RunService.Heartbeat:Connect(function(dt)
	spin += SPIN_RADIANS_PER_SEC * dt

	-- Pick up any tagged battery we're not animating yet. Doing this every frame
	-- (instead of once at startup) means we don't have to guess when the model,
	-- its tag, its attribute and its parts have all replicated to us -- track()
	-- just succeeds on the first frame everything is present.
	for _, model in CollectionService:GetTagged(BATTERY_TAG) do
		if not tracked[model] then
			track(model)
		end
	end

	for model, info in tracked do
		if model.Parent == nil then
			tracked[model] = nil   -- collected / gone
		else
			-- where this battery's centre-frame should be right now
			local pivot = CFrame.new(info.center) * CFrame.Angles(0, info.phase + spin, 0) * TILT_CFRAME
			-- carry every part from its rest pose by that frame
			for part, restPose in info.parts do
				part.CFrame = pivot * restPose
			end
		end
	end
end)
