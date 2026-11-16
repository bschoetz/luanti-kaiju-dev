local S = core.get_translator("mothra")
local mcl_mobs = kaiju_core.mcl_mobs -- (Mineclonia's, or the VoxeLibre layer)
local mob_class = mcl_mobs.mob_class

local SCALE = 8                -- visual_size; model ~33 units wingspan -> ~26.6 nodes
local ALTITUDE = 16            -- cruising height of her feet above ground/water
local WANDER_SPEED = 5
local ATTACK_SPEED = 9
local MIN_CLEARANCE = 10       -- never fly lower than this above the ground (she is not physical)
local CIRCLE_RADIUS = 15       -- horizontal distance kept while circling a target
local CIRCLE_HEIGHT = 11       -- above the target's head
local MAX_ALTITUDE = 60        -- circling cap above the target's ground (no endless climb over a flying Ghidorah)
local GUST_INTERVAL = 4.5
local GUST_RANGE = 24          -- horizontal reach of the gust
local GUST_DEPTH = 18          -- how far below her (measured to the victim's head) it reaches
local GUST_DAMAGE = 12
local GUST_HIT_DELAY = 0.65    -- downbeat of the "punch" animation (frame 106 at 25 fps)
local POWDER_INTERVAL = 11
local POWDER_TIME = 2.0        -- matches the "powder" animation (40 frames at 20 fps)
local POWDER_OFFSET = 5        -- she dusts from slightly beside the target, not right above its mouth
local POWDER_APPROACH = 4      -- give up closing in for the powder after this many seconds
local POWDER_RADIUS = 10
local POWDER_DEPTH = 30        -- how far below her the dust reaches

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local ground_y = kaiju_core.ground_y

local function height_of(obj)
	local cb = obj:get_properties().collisionbox
	return cb[5]
end

local function is_valid_victim(self, obj)
	if obj == self.object or not obj:is_valid() then return false end
	if obj:is_player() then
		-- a guardian: players only get hurt if they are her current enemy
		return obj == self.attack
	end
	local ent = obj:get_luaentity()
	-- no friendly fire: only monsters and her current enemy, never villagers, animals,
	-- pets or another Mothra
	if not (ent and ent.is_mob and not ent.dead and ent.name ~= "mothra:mothra") then return false end
	if obj == self.attack then return true end
	-- nor Cthulhu while he keeps the peace (he would turn on her)
	if ent.name == "cthulhu:cthulhu" and not ent.attack then return false end
	-- nor Gojira while she fights Ghidorah: he is her ally then, and stands right next to
	-- her enemy, where every gust and every cloud of powder used to hit him as well
	local enemy = ent.name == "gojira:gojira" and self.attack and self.attack:is_valid() and self.attack:get_luaentity()
	return ent.type == "monster" and not (enemy and enemy.name == "ghidorah:ghidorah")
end

-- Top of the victim's collision box, if nothing solid lies between her and it.
local function visible_top(self_pos, obj)
	local top = vector.offset(obj:get_pos(), 0, height_of(obj), 0)
	return core.line_of_sight(self_pos, top) and top
end

-- goals stay MIN_CLEARANCE above the terrain along the whole path (see kaiju_core)
local function keep_clearance(self, self_pos, dtime)
	kaiju_core.keep_clearance(self, self_pos, dtime, MIN_CLEARANCE)
end

-- Reset everything that belongs to one fight (also on a direct switch to a new target).
local function reset_attack(self)
	self._gust_hit, self._powder_time, self._powder_approach, self._powder_tick = nil, nil, nil, nil
	self._anim_lock = 0
end

------------------------------------------------------------------------
-- Mob
------------------------------------------------------------------------

local mothra = {
	description = S("Mothra"),
	type = "animal",           -- not "monster": golems leave her alone, she is neutral
	_spawn_category = "misc",
	persistent = true,
	hp_min = 350,
	hp_max = 350,
	xp_min = 150,
	xp_max = 150,
	armor = 60,
	knockback_resistance = 1.0,
	pushable = false,
	physical = false,          -- a 27-node wingspan would snag on every tree; she keeps her own altitude
	collisionbox = {-2.5, 0, -2.5, 2.5, 3.6, 2.5},
	selectionbox = {-4.5, 0, -4.5, 4.5, 4.2, 4.5},
	head_eye_height = 2.6,
	doll_size_override = {x = 0.15, y = 0.15},
	visual = "mesh",
	mesh = "mothra.glb",
	textures = {{"mothra.png"}},
	visual_size = {x = SCALE, y = SCALE},
	glow = 4,
	attack_type = "null",
	view_range = 64,
	tracking_distance = 80,
	_no_fall_damage = true,
	fire_damage = 2,
	can_ride_boat = false,
	can_ride_cart = false,
	drops = {
		{name = "mcl_mobitems:string", chance = 1, min = 12, max = 24, looting = "common"},
		{name = "mcl_nether:glowstone_dust", chance = 1, min = 8, max = 16, looting = "common"},
	},
	sounds = {
		random = {name = "mobs_mc_parrot_random", gain = 2},
		damage = {name = "mobs_mc_vex_hurt", gain = 2},
		death = {name = "mobs_mc_vex_death", gain = 2},
		attack = {name = "mobs_mc_ender_dragon_attack", gain = 2},
		shoot_attack = {name = "mobs_mc_ender_dragon_shoot", gain = 1.5},
		base_pitch = 0.45,
		distance = 80,
	},
	-- frame ranges match tools/mothra_model.py (glTF time in seconds, model exported at 1 fps)
	animation = {
		stand_start = 0, stand_end = 40, stand_speed = 20,     -- hovering
		walk_start = 50, walk_end = 80, walk_speed = 24,       -- (never used on foot)
		fly_start = 50, fly_end = 80, fly_speed = 24,
		punch_start = 90, punch_end = 120, punch_speed = 25, punch_loop = false,
		powder_start = 130, powder_end = 170, powder_speed = 20,
		die_start = 180, die_end = 210, die_speed = 10, die_loop = false,
	},
}

-- Her own flight model: steer the velocity smoothly towards self._goal. No gravity, no
-- node collisions (physical = false); keep_clearance() holds the goals above the ground.
function mothra:motion_step(dtime, moveresult, self_pos)
	if self.dead then
		kaiju_core.death_fall(self, self_pos)
		return
	end
	local want = kaiju_core.fly_velocity(self, dtime, self_pos, WANDER_SPEED)

	-- face the enemy while fighting, otherwise the flight direction
	local face = self.attack and self.attack:is_valid() and self.attack:get_pos()
	if face then
		self:look_at(face)
	elseif vector.length(vector.new(want.x, 0, want.z)) > 0.5 then
		self:set_yaw(math.atan2(want.z, want.x) - math.pi / 2)
	end
end

local function set_anim(self, name, lock)
	if self._anim_lock and self._anim_lock > 0 then return end
	self:set_animation(name)
	self._anim_lock = lock
end

local function wander(self, self_pos, dtime)
	self._wander_timer = (self._wander_timer or 0) - dtime
	local goal = self._goal
	-- a wall or a low roof in the way (keep_clearance, under a roof): another direction
	local blocked = self._blocked
	if not goal or blocked or self._wander_timer <= 0 or vector.distance(self_pos, goal) < 2 then
		local ang, dist = math.random() * 2 * math.pi, 16 + math.random() * 24
		local p = vector.offset(self_pos, math.cos(ang) * dist, 0, math.sin(ang) * dist)
		p.y = kaiju_core.cruise_y(p, self_pos.y, ALTITUDE + math.random() * 6, self.collisionbox[5])
		self._goal, self._goal_speed = p, WANDER_SPEED
		self._wander_timer = 6 + math.random() * 6
		-- keep_clearance checks the new path in this step: she never flies a moment
		-- towards a goal behind a wall (cornered, those moments added up)
		self._floor, self._blocked = nil, nil
	end
	set_anim(self, vector.distance(self_pos, self._goal) > 4 and "fly" or "stand")
end

local function wing_gust(self, self_pos)
	local fwd = core.yaw_to_dir(self.object:get_yaw())
	local hit = 0
	-- (positions are feet: the radius must also cover a tall victim whose head is in reach)
	for obj in core.objects_inside_radius(self_pos, GUST_RANGE + GUST_DEPTH) do
		local top = is_valid_victim(self, obj) and visible_top(self_pos, obj)
		if top and self_pos.y - top.y < GUST_DEPTH and top.y - self_pos.y < 8 then
			local rel = vector.subtract(top, self_pos)
			local flat_dist = vector.length(vector.new(rel.x, 0, rel.z))
			local flat = vector.normalize(vector.new(rel.x, 0, rel.z))
			-- a wide cone in front of her (and anything right underneath)
			if flat_dist < 6 or (flat_dist <= GUST_RANGE and vector.dot(flat, fwd) > 0.3) then
				mcl_util.deal_damage(obj, GUST_DAMAGE, {type = "mob", source = self.object, direct = self.object})
				if obj:is_valid() then
					local push = obj:is_player() and 14 or 22
					obj:add_velocity(vector.new(flat.x * push, 6, flat.z * push))
				end
				hit = hit + 1
			end
		end
	end
	-- dust whirled up in a cone ahead
	core.add_particlespawner({
		amount = 120, time = 0.4,
		pos = {min = vector.offset(self_pos, -6, -2, -6), max = vector.offset(self_pos, 6, 3, 6)},
		vel = {min = vector.offset(vector.multiply(fwd, 18), -4, -6, -4), max = vector.offset(vector.multiply(fwd, 26), 4, 2, 4)},
		exptime = {min = 0.8, max = 1.6},
		size = {min = 3, max = 7},
		texture = {name = "mcl_particles_smoke_anim.png^[colorize:#e9dcc0:180", alpha_tween = {0.8, 0}},
		animation = {type = "vertical_frames", aspect_w = 8, aspect_h = 8, length = -1},
	})
	return hit
end

local function scale_powder(self, self_pos)
	core.add_particlespawner({
		amount = 60, time = 0.5,
		pos = {min = vector.offset(self_pos, -9, 0, -9), max = vector.offset(self_pos, 9, 2, 9)},
		vel = {min = vector.new(-1, -7, -1), max = vector.new(1, -3, 1)},
		exptime = {min = 2, max = 4},
		size = {min = 2, max = 4},
		glow = 10,
		texture = {name = "mcl_particles_effect.png^[colorize:#f7c531:220", alpha_tween = {1, 0.2}},
	})
	local bottom = self_pos.y - POWDER_DEPTH
	for obj in core.objects_inside_radius(vector.offset(self_pos, 0, -POWDER_DEPTH / 2, 0), POWDER_DEPTH / 2 + POWDER_RADIUS) do
		if is_valid_victim(self, obj) and visible_top(self_pos, obj) then
			local p = obj:get_pos()
			if p.y >= bottom and p.y <= self_pos.y and vector.distance(vector.new(p.x, 0, p.z), vector.new(self_pos.x, 0, self_pos.z)) <= POWDER_RADIUS then
				mcl_potions.give_effect_by_level("poison", obj, 2, 6)
				mcl_util.deal_damage(obj, 1, {type = "magic", source = self.object, direct = self.object})
			end
		end
	end
end

function mothra:attack_null(attach_pos, self_pos, dtime, target_pos, line_of_sight)
	-- (check_attack sets attacking = false for every newly acquired target, also on a
	-- direct switch from one target to the next)
	if not self.attacking then
		self.attacking = true
		reset_attack(self)
		self._circle = math.random() * 2 * math.pi
		self._gust_timer = 2
		self._powder_timer = 5
	end
	self._gust_timer = self._gust_timer - dtime
	self._powder_timer = self._powder_timer - dtime

	-- circle above the enemy
	self._circle = self._circle + dtime * ATTACK_SPEED / CIRCLE_RADIUS
	local top = math.min(target_pos.y + height_of(self.attack) + CIRCLE_HEIGHT, ground_y(target_pos) + MAX_ALTITUDE)
	local powdering = self._powder_time ~= nil
	-- close in to dust, first approaching (_powder_approach), then hovering nearly overhead
	local r = (powdering or self._powder_approach) and POWDER_OFFSET or CIRCLE_RADIUS
	if not line_of_sight then
		r = 0 -- lost sight (wall, pit, hill): fly over the target until she sees it again
	end
	self._goal = vector.new(target_pos.x + math.cos(self._circle) * r, top, target_pos.z + math.sin(self._circle) * r)
	self._goal_speed = ATTACK_SPEED
	local flat_dist = vector.distance(vector.new(self_pos.x, 0, self_pos.z), vector.new(target_pos.x, 0, target_pos.z))

	if self._gust_hit then
		self._gust_hit = self._gust_hit - dtime
		if self._gust_hit <= 0 then
			self._gust_hit = nil
			wing_gust(self, self_pos)
		end
	elseif powdering then
		self._powder_time = self._powder_time - dtime
		self._powder_tick = (self._powder_tick or 0) - dtime
		if self._powder_tick <= 0 then
			self._powder_tick = 0.5
			scale_powder(self, self_pos)
		end
		if self._powder_time <= 0 then
			self._powder_time = nil
			self._anim_lock = 0
		end
	elseif self._powder_approach then
		-- the dust only starts once she is roughly overhead (or she gives up and circles on)
		self._powder_approach = self._powder_approach - dtime
		if flat_dist < POWDER_RADIUS - 2 then
			self._powder_approach = nil
			self._powder_timer = POWDER_INTERVAL
			self._powder_time = POWDER_TIME
			self._anim_lock = 0
			set_anim(self, "powder", POWDER_TIME)
			self:mob_sound("shoot_attack")
		elseif self._powder_approach <= 0 then
			self._powder_approach = nil
			self._powder_timer = POWDER_INTERVAL / 2
		else
			set_anim(self, "fly")
		end
	elseif line_of_sight and self._powder_timer <= 0 and flat_dist < CIRCLE_RADIUS + 4 then
		self._powder_approach = POWDER_APPROACH
	elseif line_of_sight and self._gust_timer <= 0 and flat_dist <= GUST_RANGE then
		self._gust_timer = GUST_INTERVAL
		self._gust_hit = GUST_HIT_DELAY
		self._anim_lock = 0
		set_anim(self, "punch", 1.2)
		self:mob_sound("attack")
	else
		set_anim(self, "fly")
	end
end

-- Own AI loop (ghast pattern): fight if there is a target, otherwise roam the sky.
function mothra:run_ai(dtime)
	local self_pos = self.object:get_pos()
	if self._anim_lock then
		self._anim_lock = self._anim_lock - dtime
	end
	if self:check_attack(self_pos, dtime) then
		keep_clearance(self, self_pos, dtime)
		return
	end
	if self.attacking then
		self.attacking = nil
		reset_attack(self)
	end
	local retreat = kaiju_core.retreat_goal(self)
	if retreat then
		-- Truce after Ghidorah's death (kaiju_core.start_truce): cruise to the goal. In legs of
		-- 30 nodes, so keep_clearance samples the terrain as densely as on a wander. The next
		-- leg (and its ground raycast) is only due when this one is nearly flown.
		local leg = self._goal == self._retreat_leg and self._goal
		if not leg or (leg.x - self_pos.x) ^ 2 + (leg.z - self_pos.z) ^ 2 < 25 then
			local d = vector.subtract(retreat, self_pos)
			local p = vector.add(self_pos, vector.multiply(d, math.min(1, 30 / vector.length(d))))
			p.y = kaiju_core.cruise_y(p, self_pos.y, ALTITUDE, self.collisionbox[5])
			self._goal, self._goal_speed, self._retreat_leg = p, WANDER_SPEED, p
		end
		set_anim(self, "fly")
	else
		self._retreat_leg = nil
		wander(self, self_pos, dtime)
	end
	keep_clearance(self, self_pos, dtime)
end
mothra.get_active_target = kaiju_core.get_active_target -- none while she retreats

local function hunts(self, self_pos, obj, ent)
	return ent and ent.name == "gojira:gojira"
end
local function guards_against(self, self_pos, obj, ent)
	return ent and ent.type == "monster" and ent.name ~= "cthulhu:cthulhu"
end

-- Cthulhu only while he is after someone else or holds a victim: she guards, she doesn't
-- hunt him. The nearest-target rule keeps a target it has without asking the predicate
-- again, so the wrapper drops him as soon as he calms down (or only fights her back).
local function cthulhu_aggressive(self, self_pos, obj, ent)
	return ent and ent.name == "cthulhu:cthulhu" and ((ent.attack and ent.attack ~= self.object) or ent._grab_t) and true
end
local nearest_cthulhu = mcl_mobs.build_nearest_target_rule("mob", cthulhu_aggressive, nil, nil, nil)
local function guards_against_cthulhu(self, self_pos, dtime, obj, is_current)
	if is_current and not cthulhu_aggressive(self, self_pos, obj, obj:get_luaentity()) then return nil end
	return nearest_cthulhu(self, self_pos, dtime, obj, is_current)
end

-- First matching rule wins: Ghidorah, then Gojira whenever he is in sight, then whoever
-- attacked her (never another Mothra), then Cthulhu while he is aggressive, then any other
-- monster.
local function hunts_ghidorah(self, self_pos, obj, ent)
	return ent and ent.name == "ghidorah:ghidorah"
end

mothra._targeting_rules = {
	-- Ghidorah first: in the films Mothra and Godzilla team up against him
	mcl_mobs.build_nearest_target_rule("mob", hunts_ghidorah, nil, nil, nil),
	mcl_mobs.build_nearest_target_rule("mob", hunts, nil, nil, nil),
	mcl_mobs.build_retaliation_target_rule({"mothra:mothra"}, false, nil),
	guards_against_cthulhu,
	mcl_mobs.build_nearest_target_rule("mob", guards_against, nil, nil, nil),
}

kaiju_core.no_knockback(mothra) -- punches/arrows must not zero her velocity
mcl_mobs.register_mob("mothra:mothra", mothra)

-- Egg only: no natural spawner is registered.
mcl_mobs.register_egg("mothra:mothra", S("Mothra"), "#e8811a", "#1e1612", 0)
