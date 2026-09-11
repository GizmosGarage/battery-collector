--[[
	BatteryCollision  --  LocalScript
	Location: StarterPlayer > StarterPlayerScripts

	Once your carry capacity is full, you can't pick up any more batteries
	anyway (BatterySpawner just ignores the touch) -- so bumping into their
	solid bodies is pure annoyance. This turns OFF collision on a battery's
	visible parts while you're full, and back ON once you have room again, so
	you walk straight through instead of getting blocked.

	The invisible Hitbox that actually detects pickups already has
	CanCollide = false and is untouched here -- this only affects the solid
	body (lower_body/upper_body/top_cap/terminal).

	This is entirely CLIENT-SIDE: we only set CanCollide on THIS player's own
	copy of each battery. A character's movement is simulated on the machine
	that owns it, so turning collision off locally lets *you* walk through
	while another player whose capacity still has room keeps feeling it solid.
--]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage:WaitForChild("Upgrades"))

local BATTERY_TAG = "BatteryPickup"   -- must match BatterySpawner on the server
local PART_COUNT = 5                  -- wait for the whole battery to replicate first

local LocalPlayer = Players.LocalPlayer

-- battery Model -> { the 4 solid body parts (everything except Hitbox) }
local tracked = {}

-- Are WE currently full? (carrying >= our Capacity upgrade's limit)
local function isFull()
	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	local carried = leaderstats and leaderstats:FindFirstChild("Batteries")
	if not carried then
		return false
	end
	local maxCarry = Upgrades.effect("Capacity", LocalPlayer:GetAttribute("CapacityLevel") or 0)
	return carried.Value >= maxCarry
end

local function applyCollision(parts, full)
	for _, part in parts do
		part.CanCollide = not full
	end
end

-- Try to start managing a battery. Bails (to retry next frame) until all of its
-- parts have replicated to us.
local function track(model)
	if tracked[model] then
		return
	end

	local solidParts = {}
	local totalParts = 0
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

	tracked[model] = solidParts
	applyCollision(solidParts, isFull())   -- match our CURRENT state right away
end

-- Re-apply to every battery we know about, e.g. after our full/not-full state changes.
local function refreshAll()
	local full = isFull()
	for _, parts in tracked do
		applyCollision(parts, full)
	end
end

RunService.Heartbeat:Connect(function()
	for _, model in CollectionService:GetTagged(BATTERY_TAG) do
		if not tracked[model] then
			track(model)
		end
	end

	for model in tracked do
		if model.Parent == nil then
			tracked[model] = nil   -- collected / expired, forget it
		end
	end
end)

-- Whenever what we're carrying changes (collect, dump) or our Capacity upgrade
-- changes, our full/not-full state might have flipped -- refresh everything.
task.spawn(function()
	local leaderstats = LocalPlayer:WaitForChild("leaderstats")
	leaderstats:WaitForChild("Batteries").Changed:Connect(refreshAll)
end)
LocalPlayer:GetAttributeChangedSignal("CapacityLevel"):Connect(refreshAll)
