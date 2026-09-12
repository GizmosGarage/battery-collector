--[[
	GPUs  --  ModuleScript, lives in ReplicatedStorage (shared)

	The single source of truth for the GPU catalog (what a GPU costs, what
	it pays, and how much power it draws), for the data center SPACE tiers
	that cap how many equipment slots a player could ever have, and for the
	flat price of an individual SLOT within whatever space they've got.

	Three separate purchases, three separate purposes (see the Data Center
	Shop and GPU Shop in ShopUI.client.lua):
	  1. SPACE (`GPUs.spaceTiers`) -- how big the building is. Buying a
	     bigger space just raises the SLOT CEILING; it doesn't hand you any
	     new slots by itself.
	  2. SLOTS (`GPUs.SLOT_PRICE`) -- an installation point within whatever
	     space you've got. Flat price per slot, capped by your current
	     space tier's `maxSlots`. The very first slot is free (see
	     Shop.server.lua's default rig) and starts with a free Starter GPU
	     already in it.
	  3. GPUs (`GPUs.catalog`) -- the hardware itself, bought from this
	     catalog and installed into a slot you already own.

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
GPUs.catalog = {
	{ id = "Starter",    name = "Starter GPU",        price = 100,    cashPerSec = 5,   powerDraw = 40 },
	{ id = "Basic",      name = "Basic AI GPU",       price = 1500,   cashPerSec = 12,  powerDraw = 80 },
	{ id = "Advanced",   name = "Advanced AI GPU",    price = 12500,  cashPerSec = 28,  powerDraw = 160 },
	{ id = "DataCenter", name = "Data Center GPU",    price = 100000, cashPerSec = 65,  powerDraw = 320 },
	{ id = "Neural",     name = "Neural Accelerator", price = 750000, cashPerSec = 150, powerDraw = 640 },
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

-- Data center SPACE -- how big the building is, which is what caps how
-- many equipment SLOTS could ever fit in it. Buying into a bigger tier
-- only raises that ceiling; it doesn't hand you any new slots by itself
-- (see GPUs.SLOT_PRICE below) -- so a player who wants more GPUs running
-- has to buy both the room for a slot AND the slot itself. Ordered
-- smallest/cheapest first -- index 1 (free) is what every player starts
-- with, matching the 4-slot ceiling the game always had before space
-- became its own purchase.
GPUs.spaceTiers = {
	{ name = "Starter Room",      maxSlots = 4,  price = 0 },
	{ name = "Small Server Room", maxSlots = 8,  price = 5000 },
	{ name = "Server Hall",       maxSlots = 16, price = 50000 },
	{ name = "Data Center Floor", maxSlots = 32, price = 500000 },
}

-- The largest a data center could ever get -- the last tier's maxSlots.
-- Nothing needs this as a per-player limit (a player's own CURRENT tier
-- already caps how many slots THEY can buy -- see GPUs.maxSlotsForTier);
-- it's the absolute ceiling scripts use to size things that have to cover
-- every slot ANY player could ever have (e.g. how many "SlotNGPU"
-- attributes to publish).
GPUs.MAX_SLOTS = GPUs.spaceTiers[#GPUs.spaceTiers].maxSlots

-- How many slots a given space tier (1..#GPUs.spaceTiers) has room for.
function GPUs.maxSlotsForTier(tierIndex)
	local tier = GPUs.spaceTiers[tierIndex]
	return tier and tier.maxSlots
end

-- Cash price for ONE equipment slot -- flat, regardless of how many you
-- already have (unlike space, which gets pricier per tier). The very
-- first slot is free (see Shop.server.lua's default rig); every slot
-- after that, up to your current space tier's maxSlots, costs this.
GPUs.SLOT_PRICE = 100

return GPUs
