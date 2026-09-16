--[[
	BatteryCollision  --  LocalScript
	Location: StarterPlayer > StarterPlayerScripts

	Batteries are picked up through an invisible Hitbox part (CanCollide =
	false, set on the server) that overlaps the battery's visible body --
	touching THAT is what BatterySpawner checks to award a pickup. The
	visible body itself (lower_body/upper_body/top_cap/terminal) doesn't
	need to be solid for that to work, and leaving it solid means a running
	player has to physically climb over it for a beat before the pickup
	(or the "capacity full, nothing happens" check) resolves -- killing
	momentum every time.

	So this turns CanCollide OFF on every battery's visible body parts, for
	good, the moment each one replicates to us. Players just run straight
	through: if they have room, BatterySpawner's Hitbox.Touched collects it
	and it vanishes; if they're full, it simply stays put, uninterrupted.

	This is entirely CLIENT-SIDE: we only set CanCollide on THIS player's
	own copy of each battery, which is enough -- collision is simulated on
	whichever machine owns the character walking through it.
--]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local BATTERY_TAG = "BatteryPickup"   -- must match BatterySpawner on the server
local PART_COUNT = 5                  -- wait for the whole battery to replicate first

-- battery Models we've already handled, so we don't redo the work every frame
local handled = {}

-- Try to disable collision on one battery. Bails (to retry next frame) until
-- all of its parts have replicated to us.
local function handle(model)
	if handled[model] then
		return
	end

	local totalParts = 0
	local solidParts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			totalParts += 1
			if part.Name ~= "Hitbox" then
				table.insert(solidParts, part)
			end
		end
	end
	if totalParts < PART_COUNT then
		return
	end

	for _, part in solidParts do
		part.CanCollide = false
	end
	handled[model] = true
end

RunService.Heartbeat:Connect(function()
	for _, model in CollectionService:GetTagged(BATTERY_TAG) do
		if not handled[model] then
			handle(model)
		end
	end
end)

CollectionService:GetInstanceRemovedSignal(BATTERY_TAG):Connect(function(model)
	handled[model] = nil   -- collected / expired, forget it
end)
