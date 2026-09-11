--[[
	BatteryGlow  --  LocalScript
	Location: StarterPlayer > StarterPlayerScripts

	Purely cosmetic: gives every battery a glow that signals its RARITY (and so
	its mAh value) at a glance, since the four sizes can look similar from afar.
	Escalating by tier:

		1 AAA (commonest) -- small, STATIC gold glow
		2 AA               -- bigger glow that gently PULSES
		3 C                 -- bigger + brighter, still pulses, + white sparkle PARTICLES
		4 D  (rarest)       -- biggest, most solid-looking glow, pulses, particles

	The glow is built as children of the battery model itself, so when the server
	destroys a collected battery, the glow (light, particles, all of it) is
	destroyed right along with it -- no separate cleanup needed. Runs on the
	client: purely visual, no network cost, same reasoning as BatterySpin.
--]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local BATTERY_TAG = "BatteryPickup"   -- must match BatterySpawner on the server
local PART_COUNT = 5                  -- wait for the whole battery to replicate before glowing it

-- One entry per rarity rank (1 = commonest .. 4 = rarest), matching the "Rarity"
-- attribute BatterySpawner sets on each battery.
local TIERS = {
	[1] = {   -- AAA: static
		color = Color3.fromRGB(255, 205, 90),
		glowScale = 1.6, transparency = 0.85, brightness = 1,
		pulse = false,
		particles = false,
	},
	[2] = {   -- AA: bigger, motion
		color = Color3.fromRGB(255, 200, 80),
		glowScale = 2.0, transparency = 0.80, brightness = 1.5,
		pulse = true, pulseAmplitude = 0.15, pulseSpeed = 1.2,
		particles = false,
	},
	[3] = {   -- C: bigger, brighter, white sparkle particles
		color = Color3.fromRGB(255, 215, 130),
		glowScale = 2.6, transparency = 0.70, brightness = 2.5,
		pulse = true, pulseAmplitude = 0.18, pulseSpeed = 1.4,
		particles = true, particleColor = Color3.fromRGB(255, 250, 235),
	},
	[4] = {   -- D: biggest, most solid gold
		color = Color3.fromRGB(255, 195, 60),
		glowScale = 3.4, transparency = 0.50, brightness = 4,
		pulse = true, pulseAmplitude = 0.22, pulseSpeed = 1.6,
		particles = true, particleColor = Color3.fromRGB(255, 245, 210),
	},
}

-- battery Model -> { glow = Part, baseSize = number, tier = table, phase = number }
local tracked = {}
local clock = 0

-- Build the glow ball (+ light, + optional sparkle particles) for one battery.
local function buildGlow(battery, center, tier)
	local lowerBody = battery:FindFirstChild("lower_body")
	local diameter = lowerBody and lowerBody.Size.Y or 1.5
	local glowSize = diameter * tier.glowScale

	local glow = Instance.new("Part")
	glow.Name = "RarityGlow"
	glow.Shape = Enum.PartType.Ball
	glow.Material = Enum.Material.Neon
	glow.Color = tier.color
	glow.Transparency = tier.transparency
	glow.Size = Vector3.new(glowSize, glowSize, glowSize)
	glow.CFrame = CFrame.new(center)
	glow.Anchored = true      -- never falls, never physically simulated
	glow.CanCollide = false   -- never blocks the player from walking through
	glow.CanQuery = false
	glow.CanTouch = false     -- never triggers anything's .Touched
	glow.CastShadow = false
	glow.Parent = battery

	local light = Instance.new("PointLight")
	light.Color = tier.color
	light.Brightness = tier.brightness
	light.Range = glowSize * 2.5
	light.Parent = glow

	if tier.particles then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1), tier.particleColor)
		sparkle.LightEmission = 1   -- additive-ish blend, reads as a bright glint instead of a flat dot
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.6, 0.22),
			NumberSequenceKeypoint.new(1, 0.05),
		})
		sparkle.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 1),
		})
		sparkle.Lifetime = NumberRange.new(0.9, 1.6)
		sparkle.Rate = 22
		sparkle.Speed = NumberRange.new(1, 2.5)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Parent = glow
	end

	return glow, glowSize
end

-- Try to start glowing a battery. Bails (to retry next frame) until its centre,
-- rarity, and all its parts have replicated to us.
local function track(model)
	if tracked[model] then
		return
	end

	local center = model:GetAttribute("SpawnCenter")
	local rarity = model:GetAttribute("Rarity")
	if not center or not rarity then
		return
	end
	local tier = TIERS[rarity]
	if not tier then
		return
	end

	local partCount = 0
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			partCount += 1
		end
	end
	if partCount < PART_COUNT then
		return
	end

	local glow, baseSize = buildGlow(model, center, tier)
	tracked[model] = {
		glow = glow,
		baseSize = baseSize,
		tier = tier,
		phase = math.random() * 2 * math.pi,   -- so pulsing batteries aren't in sync
	}
end

RunService.Heartbeat:Connect(function(dt)
	clock += dt

	for _, model in CollectionService:GetTagged(BATTERY_TAG) do
		if not tracked[model] then
			track(model)
		end
	end

	for model, info in tracked do
		if model.Parent == nil then
			tracked[model] = nil   -- collected / gone -- its glow went with it automatically
		elseif info.tier.pulse then
			local factor = 1 + math.sin(clock * info.tier.pulseSpeed + info.phase) * info.tier.pulseAmplitude
			local s = info.baseSize * factor
			info.glow.Size = Vector3.new(s, s, s)
		end
	end
end)
