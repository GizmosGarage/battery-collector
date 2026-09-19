--[[
	GPUs  --  ModuleScript, lives in ReplicatedStorage (shared)

	The single source of truth for the GPU catalog (what a GPU costs, what
	it pays, and how much power it draws) and for the data center SPACE
	tiers that cap how many equipment slots a player has.

	Two separate purchases, two separate purposes (see the Data Center Shop
	and GPU Shop in ShopUI.client.lua):
	  1. SPACE -- how big the building is -- is itself TWO independent
	     purchases at the Data Center Shop now:
	       a. a RACK (`GPUs.rackPrice`) -- buys one more physical
	          Server_Rack's worth of equipment slots (`SLOTS_PER_RACK` each).
	          Rack 1 is free (every player starts with it, and the free
	          Starter GPU already installed in its first slot).
	       b. a FLOOR upgrade (`GPUs.floorTiers`) -- buys ROOM for 16 more
	          racks (a whole physical row, spanning all 4 columns built in
	          the world), without buying those racks themselves -- it just
	          raises the ceiling `GPUs.maxRacksForTier` lets rack purchases
	          reach.
	     `unlockedSlots` is always `racksOwned * SLOTS_PER_RACK` (Shop.
	     server.lua) -- there's no separate per-slot purchase.
	  2. GPUs (`GPUs.catalog`) -- the hardware itself, bought from the GPU
	     Shop (always into storage) and installed into a specific slot by
	     walking up to the Server_Rack that owns it (RackShopUI.client.lua).

	Each GPU tier roughly DOUBLES the power draw of the one before it, but
	pays slightly MORE than double the Cash/sec -- "one better card beats
	two of the last one, by a little" -- so upgrading is a real gain
	without making the card it replaces worthless. The tradeoff space
	buying opens up: fill more (cheap) slots with cheap GPUs, or spend more
	on efficient GPUs that fit in the space you've already got. Both
	`server/DataCenter.server.lua` (the payout math) and
	`server/Shop.server.lua` (purchases) `require` this, so the numbers can
	never disagree.
--]]

local GPUs = {}

-- Ordered cheapest/commonest first.
--   price      -- Cash to BUY one (the very first Starter is free -- see
--                 Shop.server.lua; every purchase after that, including a
--                 second Starter, costs this)
--   cashPerSec -- Cash paid per second this GPU has enough power to run
--   powerDraw  -- mAh/sec it costs to keep this GPU running
--   color      -- this GPU's own shade, brighter/richer the higher the
--                 tier -- GPURackDisplay.client.lua paints the physical
--                 card's front panel (the bracket the DVI-D/DisplayPort/
--                 HDMI ports sit in) this color, so a glance at a rack
--                 tells you which tier is installed in each slot
GPUs.catalog = {
	{ id = "Starter",    name = "Starter GPU",        price = 100,    cashPerSec = 5,   powerDraw = 40,  color = Color3.fromRGB(155, 163, 175) },
	{ id = "Basic",      name = "Basic AI GPU",       price = 1500,   cashPerSec = 12,  powerDraw = 80,  color = Color3.fromRGB(46, 190, 115) },
	{ id = "Advanced",   name = "Advanced AI GPU",    price = 12500,  cashPerSec = 28,  powerDraw = 160, color = Color3.fromRGB(45, 140, 245) },
	{ id = "DataCenter", name = "Data Center GPU",    price = 100000, cashPerSec = 65,  powerDraw = 320, color = Color3.fromRGB(165, 85, 235) },
	{ id = "Neural",     name = "Neural Accelerator", price = 750000, cashPerSec = 150, powerDraw = 640, color = Color3.fromRGB(245, 185, 45) },
}

-- Look a catalog entry up by id -- what every other script actually does
-- with a GPU id stored on a player (an attribute, so it has to be a plain
-- string, not the table itself).
local byId = {}
for _, gpu in GPUs.catalog do
	byId[gpu.id] = gpu
end
function GPUs.get(id)
	return byId[id]
end

-- The id every player starts with, already installed in their one free slot.
GPUs.STARTER_ID = "Starter"

-- How many equipment slots ONE physical Server_Rack in the world holds.
-- Equipping now only happens by walking up to a specific rack (see
-- RackShopUI.client.lua) -- Shop.server.lua needs to know which of a
-- player's flat "Slot<N>GPU" numbers belong to "the rack you're standing
-- at", and GPURackDisplay.client.lua needs the same grouping to show the
-- right physical card in the right slot. Both read it from here so a
-- future rack size change can't leave the two disagreeing.
GPUs.SLOTS_PER_RACK = 4

-- How many racks ONE physical column holds in the world -- 4 rows deep.
-- A purely PHYSICAL fact (unlike the floor tiers below, which are
-- ECONOMIC caps on top of it) -- GPURackDisplay.client.lua needs this to
-- know how far column 1's floor could ever grow, which is no longer the
-- same number as floorTiers[1].maxRacks now that the starter tier caps
-- out well short of a full column.
GPUs.RACKS_PER_COLUMN = 16

-- FLOOR tiers -- how many RACKS the building has room for, not how many a
-- player has actually bought (see GPUs.rackPrice for that). Index 1
-- (free) is what every player starts with, and it's deliberately tight --
-- just the FIRST ROW (4 racks) of column 1, not the whole column -- so a
-- brand new player hits a real wall at 4 racks and has to buy into the
-- floor itself to keep going. Tier 2, the first paid upgrade, reveals
-- just the SECOND row (racks 5-8, 8 total) -- still column 1, still no
-- new column, just one more row of the column a player can already see,
-- for a cheap first taste of what buying floor room does. Tier 3
-- finishes out the rest of column 1 (rows 3-4, racks 9-16) -- a
-- player's second floor upgrade fills in the column they've now seen
-- two rows of. Tier 4 adds column 2 (16 more racks, 32 total). Tier 5 --
-- the LAST upgrade there is -- adds BOTH remaining columns (3 and 4) at
-- once, straight to the 64-rack ceiling: only 4 floor upgrades exist in
-- total (tiers 2-5), not one per row/column, so there's no separate
-- 48-rack checkpoint. It's still named "Column 4" (not "Columns 3-4")
-- to match every other column tier's naming, which names the LAST
-- column the upgrade gives room for, not how many columns that
-- particular purchase adds. This matches the world, which has 64
-- Server_Racks built as 4 columns side by side, so Column 4 is the
-- ceiling either way.
--
-- Racks are numbered COLUMN first (left to right), then ROW within a
-- column (front to back) -- see GPUs.sortRacks, which both
-- RackShopUI.client.lua and GPURackDisplay.client.lua use. So buying up
-- through rack 4 fills in column 1's front row before rack 5 (row 2) is
-- even reachable -- these tier names track that exactly.
GPUs.floorTiers = {
	{ name = "Starter Row", maxRacks = 4,  price = 0 },
	{ name = "Row 2",       maxRacks = 8,  price = 5000 },
	{ name = "Column 1",    maxRacks = 16, price = 25000 },
	{ name = "Column 2",    maxRacks = 32, price = 250000 },
	{ name = "Column 4",    maxRacks = 64, price = 25000000 },
}

-- The largest a data center could ever get -- the last floor tier's
-- maxRacks. Nothing needs this as a per-player limit (a player's own
-- CURRENT floor tier already caps how many racks THEY can buy -- see
-- GPUs.maxRacksForTier); it's the absolute ceiling scripts use to size
-- things that have to cover every slot ANY player could ever have (e.g. how
-- many "SlotNGPU" attributes to publish).
GPUs.MAX_RACKS = GPUs.floorTiers[#GPUs.floorTiers].maxRacks
GPUs.MAX_SLOTS = GPUs.MAX_RACKS * GPUs.SLOTS_PER_RACK

-- How many racks a given floor tier (1..#GPUs.floorTiers) has room for.
function GPUs.maxRacksForTier(tierIndex)
	local tier = GPUs.floorTiers[tierIndex]
	return tier and tier.maxRacks
end

-- The Cash cost to buy rack number `rackNumber` (2, 3, 4, ... -- rack 1 is
-- always free, same free-Starter-slot deal the game always had). Doubling
-- EVERY rack (like the original 9-rack version did) would reach absurd
-- numbers by rack 64, so instead it doubles every RACKS_PER_PRICE_STEP
-- racks -- still the same "roughly doubles" feel as the GPU catalog above,
-- just stretched out to fit a much bigger ceiling. The floor tiers above
-- stay the big, expensive structural gates; racks are the smaller,
-- steadily-climbing purchase that fills each floor in.
GPUs.RACK_BASE_PRICE = 1000
GPUs.RACKS_PER_PRICE_STEP = 8
function GPUs.rackPrice(rackNumber)
	if rackNumber <= 1 then
		return 0
	end
	local step = (rackNumber - 2) // GPUs.RACKS_PER_PRICE_STEP
	return GPUs.RACK_BASE_PRICE * 2 ^ step
end

-- The global slot-number range (inclusive) that rack `rackIndex` covers --
-- racks are numbered 1, 2, 3... in GPUs.sortRacks order (see below). Rack 1
-- is slots 1..SLOTS_PER_RACK, rack 2 is the next SLOTS_PER_RACK, and so on
-- -- pure arithmetic, so the server never needs to know where a rack
-- actually sits in the world, only which NUMBER it is.
function GPUs.rackSlotRange(rackIndex)
	local first = (rackIndex - 1) * GPUs.SLOTS_PER_RACK + 1
	return first, first + GPUs.SLOTS_PER_RACK - 1
end

-- Puts a list of Server_Rack instances into canonical rack-number order --
-- COLUMN first (left to right), then ROW within a column (front to back,
-- smallest Z first), then left-to-right among any racks that still tie.
-- RackShopUI.client.lua and GPURackDisplay.client.lua both call this
-- instead of each keeping their own comparator, so "rack 2's panel" and
-- "rack 2's physical cards" can never quietly drift out of agreement.
--
-- Columns aren't hard-coded positions -- they're DETECTED from the actual
-- gap between racks' X positions: touching racks (same column) differ by
-- about one rack's width; a jump of more than COLUMN_GAP_THRESHOLD studs
-- means a new column started. This reads the world instead of assuming
-- any particular layout, so moving/adding/re-spacing columns in Studio
-- later needs no code change here.
local COLUMN_GAP_THRESHOLD = 8   -- studs -- bigger than one rack touching the next, smaller than the gap between columns
function GPUs.sortRacks(racks)
	local sorted = table.clone(racks)
	table.sort(sorted, function(a, b)
		return a.Position.X < b.Position.X
	end)

	local columnOf = {}
	local column = 1
	local previousX = nil
	for _, rack in sorted do
		if previousX and (rack.Position.X - previousX) > COLUMN_GAP_THRESHOLD then
			column += 1
		end
		columnOf[rack] = column
		previousX = rack.Position.X
	end

	table.sort(sorted, function(a, b)
		local columnA, columnB = columnOf[a], columnOf[b]
		if columnA ~= columnB then
			return columnA < columnB
		end
		if a.Position.Z ~= b.Position.Z then
			return a.Position.Z < b.Position.Z
		end
		return a.Position.X < b.Position.X
	end)

	return sorted
end

-- Waits for (up to WAIT_TIMEOUT seconds) and returns EVERY Server_Rack in
-- Workspace, in canonical rack-number order. Racks stream into the
-- client one at a time -- a script that scans Workspace only once, right
-- after the FIRST one appears, can easily catch some racks but not
-- others still in transit, and since it never scans again, those
-- stragglers stay uncounted (and un-hidden/un-shown) for the rest of the
-- session. Polling until the full GPUs.MAX_RACKS count actually shows up
-- (or giving up after the timeout, rather than hanging forever if a rack
-- is missing for a real reason) is what RackShopUI.client.lua and
-- GPURackDisplay.client.lua both call this for, instead of each doing
-- its own one-shot GetChildren() scan.
--
-- PREFERS each rack's own "RackNumber" attribute (stamped once,
-- SERVER-side, by RackNumbering.server.lua, from the TRUE built layout)
-- over re-deriving order from GPUs.sortRacks' live-position gap
-- detection. That detection is only safe on a layout no one has ever
-- nudged -- once GPURackDisplay.client.lua starts flushing columns
-- together (tier 4+, spacing every column the same distance apart --
-- see computeColumnOffsets in GPURackDisplay.client.lua), a shifted
-- column can end up closer to its neighbor than COLUMN_GAP_THRESHOLD,
-- and a live re-scan at that point misreads two columns as one merged
-- column, scrambling every rack number from there on. The server never
-- moves a rack (only this client-side illusion does), so its stamped
-- numbers are immune to that regardless of when this function happens
-- to run relative to any of those shifts. Falls back to sortRacks only
-- if the attributes genuinely aren't there yet (e.g. RackNumbering.
-- server.lua hasn't run, or hasn't
-- replicated to this client) rather than hanging forever.
--
-- MEMOIZED -- the first call's result is cached and handed back as-is to
-- every later call, in EITHER script, for the rest of this client
-- session, so "rack N" can never quietly renumber partway through.
local RACK_WAIT_TIMEOUT = 10
local cachedRacks = nil
function GPUs.getAllRacks()
	if cachedRacks then
		return cachedRacks
	end
	local deadline = os.clock() + RACK_WAIT_TIMEOUT
	local found
	local allNumbered
	repeat
		found = {}
		for _, child in workspace:GetChildren() do
			if child.Name == "Server_Rack" and child:IsA("BasePart") then
				table.insert(found, child)
			end
		end
		allNumbered = #found >= GPUs.MAX_RACKS
		if allNumbered then
			for _, rack in found do
				if not rack:GetAttribute("RackNumber") then
					allNumbered = false
					break
				end
			end
		end
		if allNumbered then
			break
		end
		task.wait()
	until os.clock() >= deadline

	if allNumbered then
		local sorted = table.clone(found)
		table.sort(sorted, function(a, b)
			return a:GetAttribute("RackNumber") < b:GetAttribute("RackNumber")
		end)
		cachedRacks = sorted
	else
		cachedRacks = GPUs.sortRacks(found)
	end
	return cachedRacks
end

-- The X-coordinate the data center's Pad and Sign should sit at for a
-- given floor tier -- centered on whichever columns that tier actually
-- covers (just column 1 at tiers 1-3, whether that's 4, 8, or all 16 of
-- its racks; column 1 THROUGH the last column tier 4+ unlocks), not
-- always column 1's own center. This is the ONE
-- formula both GPURackDisplay.client.lua (moves the Pad/Sign there,
-- visually, per player -- see its updatePlatform for the matching floor
-- width) and DataCenter.server.lua (checks deposits against that SAME
-- per-player X) ever compute this from, so they can never quietly
-- disagree about where "the pad" is for a given player. That agreement
-- matters more here than it does for the racks: the shared Pad instance
-- can only ever be in one TRUE position at a time, so unlike a rack's
-- visibility (purely a per-client illusion), the deposit trigger has to
-- be recomputed the same way, per player, on the SERVER -- a plain
-- `pad.Touched` can't do that (see the README for why one static
-- position was tried and reverted twice before this).
--
-- `rightIndex`, at tiers 1-3 (only column 1 covered), is whichever rack
-- CAPACITY reveals -- not always rack 4. That matters now that tier 2
-- spreads two of column 1's built ROWS out SIDE BY SIDE instead of
-- stacking them front-to-back (see GPURackDisplay.client.lua's
-- computeRowOffsets): rack 8 (tier 2's last rack) needs to be the RIGHT
-- reference, not rack 4, or this would only ever measure the FIRST row's
-- own width and miss the second row entirely. This still gives the
-- exact same answer as before for tiers 1 and 3 (racks 4 and 16 sit at
-- the SAME X as rack 4 always did, since every row in column 1 shares
-- one X footprint -- only ROW 2's rack GROUP gets moved sideways by
-- GPURackDisplay.client.lua, and it's moved a SYMMETRIC amount from
-- row 1's, so this formula lands on the same center whether it reads
-- racks' TRUE positions (as DataCenter.server.lua always does -- the
-- server never moves a rack) or their client-shifted ones.
function GPUs.dataCenterCenterX(floorTier, racks)
	local capacity = GPUs.maxRacksForTier(floorTier) or 1
	local columnsCovered = math.max(1, capacity // GPUs.RACKS_PER_COLUMN)
	local leftRack = racks[1]
	local rightIndex
	if columnsCovered == 1 then
		rightIndex = math.min(capacity, GPUs.RACKS_PER_COLUMN, #racks)
	else
		rightIndex = math.min((columnsCovered - 1) * GPUs.RACKS_PER_COLUMN + 4, #racks)
	end
	local rightRack = racks[rightIndex]
	local leftEdge = leftRack.Position.X - leftRack.Size.X / 2
	local rightEdge = rightRack.Position.X + rightRack.Size.X / 2
	return (leftEdge + rightEdge) / 2
end

-- Add up a whole rig's combined Cash/sec and power draw -- the same sum
-- DataCenter.server.lua needs to run the payout loop for ONE player, and
-- StatusPanel.client.lua needs to show that SAME player's own numbers back
-- to them. Both scripts read GPU ids off "Slot<N>GPU" attributes, just on
-- different Instances (a server script can read any player's; a client
-- script only ever reads its own LocalPlayer's) -- `getSlotId(i)` is
-- whichever of those the caller already has, so this module never needs to
-- know about Players or attributes itself, only the catalog math.
function GPUs.rigTotals(unlockedSlots, getSlotId)
	local cashPerSec, powerDraw = 0, 0
	for i = 1, unlockedSlots do
		local id = getSlotId(i)
		local gpu = id ~= nil and id ~= "" and GPUs.get(id)
		if gpu then
			cashPerSec += gpu.cashPerSec
			powerDraw += gpu.powerDraw
		end
	end
	return cashPerSec, powerDraw
end

return GPUs
