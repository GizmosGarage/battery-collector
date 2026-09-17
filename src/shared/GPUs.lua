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

-- FLOOR tiers -- how many RACKS the building has room for, not how many a
-- player has actually bought (see GPUs.rackPrice for that). Each upgrade
-- adds a whole physical ROW -- 16 racks -- matching the world, which has 64
-- Server_Racks built (4 rows of 16, each row spanning all 4 spaced-out
-- columns), so Row 4 is the ceiling. Index 1 (free) is what every player
-- starts with.
--
-- IMPORTANT: "row" here means Z position, not the 4 left-right columns the
-- world was built in. RackShopUI.client.lua/GPURackDisplay.client.lua
-- number racks by sorting Z first, then X -- so slots unlock front-to-back
-- ACROSS the whole width (all 4 columns' first row, then all 4 columns'
-- second row, ...), not column-by-column.
GPUs.floorTiers = {
	{ name = "Row 1", maxRacks = 16, price = 0 },
	{ name = "Row 2", maxRacks = 32, price = 250000 },
	{ name = "Row 3", maxRacks = 48, price = 2500000 },
	{ name = "Row 4", maxRacks = 64, price = 25000000 },
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
-- racks are numbered 1, 2, 3... left to right in the order they're built
-- (see RackShopUI.client.lua/GPURackDisplay.client.lua, which sort the
-- actual Server_Rack parts by position to assign these numbers). Rack 1 is
-- slots 1..SLOTS_PER_RACK, rack 2 is the next SLOTS_PER_RACK, and so on --
-- pure arithmetic, so the server never needs to know where a rack actually
-- sits in the world, only which NUMBER it is.
function GPUs.rackSlotRange(rackIndex)
	local first = (rackIndex - 1) * GPUs.SLOTS_PER_RACK + 1
	return first, first + GPUs.SLOTS_PER_RACK - 1
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
