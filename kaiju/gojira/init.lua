local S = core.get_translator("gojira")
local mcl_mobs = kaiju_core.mcl_mobs -- (Mineclonia's, or the VoxeLibre layer)
local mob_class = mcl_mobs.mob_class

local SCALE = 7.5            -- visual_size; the model is ~21 units tall, 10 units = 1 node -> ~15.6 nodes
local UNIT = SCALE / 10      -- nodes per model unit
local BREATH_TIME = 2.5      -- seconds; matches the "breath" animation (50 frames at 20 fps)
local BREATH_WINDUP = 0.8    -- rear-up part of the animation before the first flame
local BREATH_COOLDOWN = 7.0
local BREATH_MIN_DIST = 9    -- closer than this he stomps/bites instead
local BREATH_MAX_DIST = 32
local FLAME_INTERVAL = 0.1
-- Mouth position in the breath pose and ground covered by one walk cycle (frames 70-110),
-- both in model units as printed by tools/gojira_model.py. mcl_mobs plays walk at
-- walk_speed * velocity fps, so walk_speed = frames per node keeps the feet planted.
local MOUTH_HEIGHT = 13.86 * UNIT
local MOUTH_FORWARD = 8.42 * UNIT
-- breath_up pose (flying targets): head pitched up 40 deg instead of down 36 deg
local MOUTH_UP_HEIGHT = 21.02 * UNIT
local MOUTH_UP_FORWARD = 3.38 * UNIT
local BREATH_UP_ANGLE = math.rad(15) -- target elevation above which he breathes upwards
local WALK_CYCLE_NODES = 10.356 * UNIT

------------------------------------------------------------------------
-- Fire breath projectile
------------------------------------------------------------------------

local flame_damage = mcl_mobs.get_arrow_damage_func(2, "fireball")

local function burn(self, obj)
	flame_damage(self, obj)
	mcl_burning.set_on_fire(obj, 6)
end

mcl_mobs.register_arrow("gojira:flame", {
	visual = "sprite",
	visual_size = {x = 1.5, y = 1.5},
	textures = {"fire_basic_flame.png"},
	velocity = 22,
	collisionbox = {-0.4, -0.4, -0.4, 0.4, 0.4, 0.4},
	glow = 14,
	_is_fireball = true,
	_lifetime = 80, -- counted in server steps, not seconds; long enough to reach BREATH_MAX_DIST
	hit_player = burn,
	hit_mob = burn,
	hit_node = function(self, pos)
		-- Ignite the air node in front of the block that was hit (blaze fireball pattern).
		local v = self.object:get_velocity()
		if vector.length(v) == 0 then return end
		local fire_pos = vector.round(vector.subtract(pos, vector.normalize(v)))
		local node = core.get_node(fire_pos)
		local def = core.registered_nodes[node.name]
		if (node.name == "air" or (def and def.buildable_to))
				and kaiju_core.griefing_enabled("gojira:gojira", "kaiju_gojira_fire")
				and not core.is_protected(fire_pos, "") then
			core.set_node(fire_pos, {name = "mcl_fire:fire"})
		end
	end,
})

------------------------------------------------------------------------
-- Mob
------------------------------------------------------------------------

local gojira = {
	description = S("Gojira"),
	type = "monster",
	_spawn_category = "misc",  -- stays out of the monster cap
	persistent = true,         -- never despawns
	hp_min = 500,
	hp_max = 500,
	xp_min = 200,
	xp_max = 200,
	armor = 40,                -- takes 40% of melee damage
	collisionbox = {-2.4, 0, -2.4, 2.4, 14.5, 2.4},
	doll_size_override = {x = 0.2, y = 0.2},
	visual = "mesh",
	mesh = "gojira.glb",
	textures = {{"gojira.png"}},
	visual_size = {x = SCALE, y = SCALE},
	makes_footstep_sound = true,
	stepheight = 1.1,
	movement_speed = 7.5,       -- measured ~6.1 nodes/s in pursuit; a sprinting player does 5.6
	pace_bonus = 0.5,
	floats = 0,                -- switched per step in check_standin (wade vs. swim)
	water_velocity = 3.0,      -- swim speed; measured ~5 nodes/s in deep water (default 0.4 is a crawl)
	damage = 18,
	reach = 7,                 -- measured from the centre, so the big body needs more
	melee_interval = 1.5,
	_attack_knockback = 3,
	attack_type = "melee",     -- melee up close; fire breath is layered on top in attack_melee
	arrow = "gojira:flame",
	view_range = 58,
	tracking_distance = 64,
	fire_resistant = true,
	_fire_resistant = true,
	fire_damage = 0,
	lava_damage = 0,
	_no_fall_damage = true,
	_melee_esp = true,         -- keeps chasing behind walls/trees instead of losing the path
	drops = {
		{name = "mcl_core:diamond", chance = 1, min = 3, max = 6, looting = "common"},
		{name = "mcl_mobitems:bone", chance = 1, min = 8, max = 16, looting = "common"},
	},
	sounds = {
		random = {name = "mobs_mc_bear_growl", gain = 2.5},
		attack = {name = "mobs_mc_bear_attack", gain = 2.5},
		war_cry = {name = "mobs_mc_wither_spawn", gain = 1.5},
		shoot_attack = {name = "mobs_mc_ender_dragon_shoot", gain = 2},
		damage = {name = "mobs_mc_bear_hurt", gain = 2},
		death = {name = "mobs_mc_wither_spawn", gain = 2},
		base_pitch = 0.55,
		distance = 80,
	},
	-- frame ranges match tools/gojira_model.py (glTF time in seconds, model exported at 1 fps)
	animation = {
		stand_start = 0, stand_end = 60, stand_speed = 15,
		walk_start = 70, walk_end = 110, walk_speed = 40 / WALK_CYCLE_NODES,
		punch_start = 120, punch_end = 140, punch_speed = 25,
		breath_start = 150, breath_end = 200, breath_speed = 20, breath_loop = false,
		breath_up_start = 250, breath_up_end = 300, breath_up_speed = 20, breath_up_loop = false,
		die_start = 210, die_end = 240, die_speed = 10, die_loop = false,
	},
}

local function mouth_pos(self, up)
	if up then return kaiju_core.model_point(self, MOUTH_UP_FORWARD, 0, MOUTH_UP_HEIGHT) end
	return kaiju_core.model_point(self, MOUTH_FORWARD, 0, MOUTH_HEIGHT)
end

-- Is the target high enough above his mouth (e.g. Mothra circling) to breathe upwards?
local function target_above(self, target_pos)
	local from = mouth_pos(self, false)
	local cb = self.attack:get_properties().collisionbox
	local dy = target_pos.y + (cb[2] + cb[5]) / 2 - from.y
	local flat = vector.distance(vector.new(from.x, 0, from.z), vector.new(target_pos.x, 0, target_pos.z))
	return math.atan2(dy, flat) > BREATH_UP_ANGLE
end

local function shoot_flame(self, target_pos)
	local from = mouth_pos(self, self._breath_up)
	local aim = vector.offset(target_pos, (math.random() - 0.5) * 2, 0.8 + math.random(), (math.random() - 0.5) * 2)
	local obj = core.add_entity(from, self.arrow)
	if not obj then return end
	local ent = obj:get_luaentity()
	obj:set_velocity(vector.multiply(vector.direction(from, aim), ent.velocity))
	ent.switch = 1
	ent.owner_id = tostring(self.object)
	ent._shooter = self.object
end

local function breath_particles(self, target_pos)
	local from = mouth_pos(self, self._breath_up)
	local v = vector.multiply(vector.direction(from, target_pos), 18)
	core.add_particlespawner({
		amount = 25, time = FLAME_INTERVAL * 2,
		pos = {min = vector.offset(from, -0.5, -0.5, -0.5), max = vector.offset(from, 0.5, 0.5, 0.5)},
		vel = {min = vector.offset(v, -2, -2, -2), max = vector.offset(v, 2, 2, 2)},
		exptime = {min = 0.6, max = 1.2},
		size = {min = 4, max = 8},
		texture = {name = "fire_basic_flame.png", alpha_tween = {1, 0}, scale_tween = {1, 2.5}},
		glow = 14,
	})
end

function gojira:attack_melee(attach_pos, self_pos, dtime, target_pos, line_of_sight)
	self._breath_cooldown = math.max((self._breath_cooldown or 0) - dtime, 0)

	if self._breath_time then
		-- Breathing fire: stand still, track the target, spray flames.
		self._breath_time = self._breath_time - dtime
		self:look_at(target_pos)
		self._flame_timer = (self._flame_timer or 0) - dtime
		if self._flame_timer <= 0 then
			self._flame_timer = FLAME_INTERVAL
			shoot_flame(self, target_pos)
			breath_particles(self, target_pos)
		end
		if self._breath_time <= 0 then
			self._breath_time = nil
			self._breath_cooldown = BREATH_COOLDOWN
			self.attacking = nil -- re-initialise the melee state machine next step
			self:set_animation("walk")
		end
		return
	end

	local dist = vector.distance(attach_pos, target_pos)
	if self._breath_cooldown == 0 and line_of_sight
			and dist >= BREATH_MIN_DIST and dist <= BREATH_MAX_DIST then
		self._breath_time = BREATH_TIME
		self._flame_timer = BREATH_WINDUP
		self._punch_animation_timeout = nil
		self:halt_in_tracks(true)
		self:cancel_navigation()
		self._breath_up = target_above(self, target_pos)
		self:set_animation(self._breath_up and "breath_up" or "breath")
		self:mob_sound("shoot_attack")
		return
	end

	kaiju_core.update_bulldoze(self, dtime, attach_pos, target_pos)
	return mob_class.attack_melee(self, attach_pos, self_pos, dtime, target_pos, line_of_sight)
end

function gojira:gopath(...)
	return kaiju_core.gopath(self, ...)
end

function gojira:attack_end()
	self._breath_time = nil
	kaiju_core.end_bulldoze(self)
	return mob_class.attack_end(self)
end

------------------------------------------------------------------------
-- Smashing through the world (respects mobs_griefing and protection)
------------------------------------------------------------------------

-- Tail segments from tools/gojira_model.py in model units: distance behind him, centre
-- height, thickness, dorsal plate height on top.
local TAIL = {
	{3.9, 8.4, 4.8, 2.8}, {6.9, 7.7, 4.2, 2.5}, {9.85, 6.4, 3.6, 2.2}, {12.75, 4.7, 3.0, 1.9},
	{15.6, 3.1, 2.4, 1.6}, {18.4, 2.0, 1.9, 1.3}, {21.15, 1.5, 1.4, 1.0}, {23.75, 1.65, 1.0, 0.7},
}
local TAIL_FIRST = 3        -- segments 1-2 stay inside the path his body already cleared

gojira._smash = {
	lookahead = 3, -- nodes ahead; at ~6 nodes/s he covers 1.5 nodes per 0.25 s smash tick
	tail = {segments = TAIL, unit = UNIT, first = TAIL_FIRST},
}

-- Chest and head carry hit boxes (kaiju_core.ensure_hitboxes): arrows only find objects
-- whose position is within 5 nodes of their path, and his position is at his feet.
-- shortcut: rest-pose positions (model units: forward, up); the head box is up to ~4 nodes
-- off the visible head while he breathes fire. Per-animation offsets if that matters.
local function hitbox_pos(fwd, up)
	return function(self) return kaiju_core.model_point(self, fwd * UNIT, 0, up * UNIT) end
end
local HITBOXES = {
	{name = "chest", pos = hitbox_pos(1.0, 13.5), box = {-3, -3.5, -3, 3, 3.5, 3}},
	{name = "head", pos = hitbox_pos(5.0, 19.0)},
}

function gojira:ai_step(dtime)
	mob_class.ai_step(self, dtime)
	if not self.dead then kaiju_core.ensure_hitboxes(self, HITBOXES) end
	kaiju_core.smash_step(self, dtime, "gojira:gojira")
end

------------------------------------------------------------------------
-- Water: he wades instead of swimming
------------------------------------------------------------------------

local SWIM_DEPTH = 10 -- nodes of water above his feet before he swims instead of wading

function gojira:check_standin(dtime, attach_pos)
	return kaiju_core.check_standin(self, dtime, attach_pos, SWIM_DEPTH)
end

function gojira:step_drowning()
	return false -- holds his breath indefinitely
end

-- Don't make detours around lakes.
gojira.gwp_penalties = table.copy(mob_class.gwp_penalties)
gojira.gwp_penalties.WATER = 0.0

-- Truce after Ghidorah's death (kaiju_core.start_truce): walk straight to the retreat goal,
-- like a bulldoze (smash_step clears the way), with no target.
local function retreat(self, self_pos, dtime)
	local goal = kaiju_core.retreat_goal(self, dtime)
	if not goal then return false end
	-- navigation_step follows a pathfinder path before the straight-line goal: drop the
	-- one that was leading him to Ghidorah, or he walks to the corpse first
	if self.waypoints or self.pathfinding_context then self:cancel_navigation() end
	self:go_to_stupidly(goal, 1)
	self:set_animation("walk")
	return true
end
gojira.get_active_target = kaiju_core.get_active_target

gojira.ai_functions = {
	mob_class.check_attack, -- (while retreating it only ends the running attack)
	retreat,
	mob_class.check_pace,
}

gojira._targeting_rules = {
	-- the archenemy comes first, even over whoever is hitting him (esp: behind walls too)
	mcl_mobs.build_nearest_target_rule("mob", {"ghidorah:ghidorah"}, nil, nil, true),
	mcl_mobs.build_retaliation_target_rule(),
	kaiju_core.cthulhu_rule(), -- only when he comes close (32 nodes) and is not under water
	-- esp: once he has seen you, hiding behind walls doesn't shake him off (he bulldozes through)
	mcl_mobs.build_nearest_target_rule("player", nil, nil, nil, true),
	mcl_mobs.build_nearest_target_rule("mobs_mc:iron_golem", {"mobs_mc:iron_golem"}, nil, nil, nil),
	mcl_mobs.build_alert_receiver_rule(),
}

-- punches and arrows must not stop him dead (see kaiju_core.no_knockback)
kaiju_core.no_knockback(gojira)
gojira.check_for_death = kaiju_core.check_for_death -- play "die", not a leftover bite

mcl_mobs.register_mob("gojira:gojira", gojira)

-- Egg only: no natural spawner is registered.
mcl_mobs.register_egg("gojira:gojira", S("Gojira"), "#2f3a2e", "#d8d6c8", 0)
