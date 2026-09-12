--[[
	GPUs  --  ModuleScript, lives in ReplicatedStorage (shared)

	The single source of truth for the GPU catalog (what a GPU costs, what
	it pays, and how much power it draws) and for the equipment SLOTS a
	player's data center run holds them in.

	This REPLACES the old flat "Cash" upgrade (Upgrades.lua) with actual
	hardware: instead of one number that goes up forever, a player has 1-4
	GPU SLOTS and fills them with GPUs bought from this catalog. Slot 1 is
	free and starts with a free Starter GPU already in it; slots 2-4 cost
	Cash to unlock (see GPUs.SLOT_PRICES), and every GPU -- including extra
	Starters -- costs its own `price` to buy.

	Each tier roughly DOUBLES the power draw of the one before it, but pays
	slightly MORE than double the Cash/sec -- "one better card beats two of
	the last one, by a little" -- so upgrading is a real gain without making
	the card it replaces worthless. Both `server/DataCenter.server.lua` (the
	payout math) and `server/Shop.server.lua` (purchases) `require` this, so
	the numbers can never disagree.

	NOTE: this is a first pass at the mechanic. Buying a GPU auto-installs
	it into the next EMPTY slot; there's no swapping an installed GPU back
	out or storing spares yet -- see CHANGELOG.md for what's deferred.
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

-- How many equipment slots exist in total, and what unlocking EACH one
-- costs -- index 1 is slot 1's price (free; it's the one every player
-- starts with), index 2 is slot 2's price, and so on.
GPUs.MAX_SLOTS = 4
GPUs.SLOT_PRICES = { 0, 500, 10000, 100000 }

-- Cash price to unlock `slotNumber` (1..MAX_SLOTS). Slot 1 is always free.
function GPUs.slotPrice(slotNumber)
	return GPUs.SLOT_PRICES[slotNumber]
end

return GPUs
