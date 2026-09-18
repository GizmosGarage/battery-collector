--[[
	RackNumbering  --  Script, lives in ServerScriptService

	Stamps a permanent "RackNumber" attribute (1, 2, 3, ...) onto every
	Server_Rack in Workspace, once, using GPUs.sortRacks on the racks'
	TRUE BUILT positions. Runs here -- on the SERVER -- specifically
	because the server never moves a rack; only GPURackDisplay.client.lua
	does, as a client-only illusion for the tier-2+ split layout, and
	that never replicates back to the server or to any other client. So
	whatever GPUs.sortRacks sees here is always the real, un-split
	layout, immune to the same gap-based detection getting confused by a
	rack that's since been nudged sideways.

	GPUs.getAllRacks() -- what GPURackDisplay.client.lua and
	RackShopUI.client.lua both actually call -- reads this attribute
	instead of re-deriving order from live positions, for exactly that
	reason. This script just has to run once, early, before those
	attributes are needed; it doesn't matter that it finishes well
	before any player joins.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GPUs = require(ReplicatedStorage:WaitForChild("GPUs"))

local RACK_WAIT_TIMEOUT = 10
local deadline = os.clock() + RACK_WAIT_TIMEOUT
local found
repeat
	found = {}
	for _, child in workspace:GetChildren() do
		if child.Name == "Server_Rack" and child:IsA("BasePart") then
			table.insert(found, child)
		end
	end
	if #found >= GPUs.MAX_RACKS then
		break
	end
	task.wait()
until os.clock() >= deadline

local sorted = GPUs.sortRacks(found)
for i, rack in sorted do
	rack:SetAttribute("RackNumber", i)
end
