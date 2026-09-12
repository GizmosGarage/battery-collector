--[[
	FieldLockDisplay  --  LocalScript
	Location: StarterPlayer > StarterPlayerScripts

	Draws each LOCKED field's Pad dimmed grey, and lights up its floating
	sign ("LOCKED -- need $X lifetime Cash, you have $Y"), for THIS PLAYER
	ONLY -- a field being locked for one player doesn't dim it for anyone
	else in the server. Same per-viewer trick DataCenterDisplay.client.lua
	uses for the Data Center's ONLINE glow: the Pad is one shared part, but
	setting its Color/Transparency LOCALLY only changes what WE see it as.

	A field unlocks PERMANENTLY once this player's LifetimeCash leaderstat
	(never decreases -- see Fields.lua and DataCenter.server.lua) reaches
	that field's Fields.lua `unlockCash`. Field_Green has no lock
	(`unlockCash` = 0) and never gets checked or a sign.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fields = require(ReplicatedStorage:WaitForChild("Fields"))

local LocalPlayer = Players.LocalPlayer

-- ============================ CONFIG ============================
local LOCKED_COLOR        = Color3.fromRGB(70, 70, 74)   -- flat grey -- reads as "inactive" on any field's normal color
local LOCKED_TRANSPARENCY = 0.35
-- ==============================================================

-- Build one field's display info: caches its Pad's TRUE (unlocked) color
-- up front -- before this script ever dims it -- so unlocking can restore
-- it exactly, without this script needing to know each field's real color
-- itself (that's world geometry, not code -- see Fields.lua's header).
-- Returns nil for a field with no lock at all (Field_Green) -- nothing to
-- build or find a sign for.
local function buildLockDisplay(def)
	if def.unlockCash <= 0 then
		return nil
	end

	local pad = Fields.getPad(def.name)
	local field = workspace:WaitForChild(def.name)
	local sign = field:WaitForChild("Sign", 5)
	local billboard = sign and sign:WaitForChild("Billboard", 5)

	return {
		def = def,
		pad = pad,
		billboard = billboard,
		status = billboard and billboard:WaitForChild("Status", 5),
		requirement = billboard and billboard:WaitForChild("Requirement", 5),
		unlockedColor = pad.Color,   -- captured BEFORE any dimming -- this IS the field's real color
	}
end

local displays = {}
for _, def in Fields.defs do
	local display = buildLockDisplay(def)
	if display then
		table.insert(displays, display)
	end
end

local function render()
	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	local lifetimeCash = leaderstats and leaderstats:FindFirstChild("LifetimeCash")
	local lifetime = lifetimeCash and lifetimeCash.Value or 0

	for _, d in displays do
		local unlocked = lifetime >= d.def.unlockCash

		d.pad.Color = unlocked and d.unlockedColor or LOCKED_COLOR
		d.pad.Transparency = unlocked and 0 or LOCKED_TRANSPARENCY

		if d.billboard then
			d.billboard.Enabled = not unlocked   -- the sign only matters while it's still locked
		end
		if not unlocked then
			if d.status then
				d.status.Text = "LOCKED"
			end
			if d.requirement then
				d.requirement.Text = string.format(
					"Need $%d lifetime Cash (have $%d)",
					d.def.unlockCash, lifetime
				)
			end
		end
	end
end

task.spawn(function()
	local leaderstats = LocalPlayer:WaitForChild("leaderstats")
	leaderstats:WaitForChild("LifetimeCash").Changed:Connect(render)
	render()
end)
