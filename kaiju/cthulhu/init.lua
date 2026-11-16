local S = core.get_translator("cthulhu")
local mcl_mobs = kaiju_core.mcl_mobs -- (Mineclonia's, or the VoxeLibre layer)
local mob_class = mcl_mobs.mob_class
local kc = kaiju_core

------------------------------------------------------------------------
-- Model-derived numbers (printed by tools/cthulhu_model.py, here in nodes; see README.md)
------------------------------------------------------------------------

local SCALE = 6
local H = 13                         -- collision box height
local WALK_CYCLE_NODES = 3.94
local FACE = {5.32, 0, 6.65}         -- stand: where the feelers start {forward, side, up}
local HOLD = {5.47, -0.17, 5.94}     -- grab clip, frame 290: between the claws of claws_r
local GRAB_CLOSE = 0.6               -- seconds into the grab clip when the claws close (frame 282)

------------------------------------------------------------------------
-- Tunables
------------------------------------------------------------------------

local HP = 550
local SEA_ENTER = 8            -- water this deep above his feet: sea mode (swims, dives)
local SEA_LEAVE = 5            -- shallower than this: back to walking and wading
local HEAD_OUT = 4             -- nodes of him above the surface while he fights
local SWIM_SPEED = 8
local CRUISE_SPEED = 5         -- on the way home
local TERRITORY = 48           -- nodes around home (horizontal): whoever is inside is an intruder
local LEASH = 72               -- nodes around home (horizontal): targets beyond it are let go
local LAND_LIMIT = 20          -- seconds of a fight spent on dry land before he gives up
local STALL_LIMIT = 12         -- seconds without getting closer to a target out of reach before he gives up
local IGNORE_TIME = 60         -- he then ignores that intruder this long (unless it hits him)
local OPEN_SKY = 8             -- natural light at noon that counts as "under the open sky"
local FLYER_HEIGHT = 3         -- a mob with more air than this under its feet is a flyer
local RETURN_TIMEOUT = 60      -- he ignores intruders at most this long on his way home
local HOME_RADIUS = 4          -- this close to home (horizontal) he has arrived
local HOME_DEPTH = H + 2       -- water this deep is deep enough for a home (he cruises 2 nodes under "submerged")
local FLEE_BELOW = 0.25        -- of HP: dive away
local FLEE_UNTIL = 0.7         -- of HP: come back
local FLEE_TIMEOUT = 180       -- seconds: he comes back anyway (home out of reach or too shallow to heal in)
local REGEN = 2                -- HP per second, at least half submerged, 5 s after the last hit
local LAND_FACTOR = 1.5        -- damage taken on dry land
local GRAB_RANGE = 10          -- from his face to the victim
local GRAB_HOLD = 6            -- seconds until he lets go
local GRAB_BREAK = 25          -- damage he takes during a grab that makes him let go
local GRAB_COOLDOWN = 10
local SQUEEZE = 2              -- damage per second to the victim
local DRAG_SPEED = 8
local AURA_RADIUS = 32         -- nausea for players this close to his head while he fights
local DARK_RADIUS = 12         -- darkness on top
local ROAR_INTERVAL = 20
local RISE_TIME = 3.0          -- "rise" clip (60 frames at 20 fps)
local ROAR_TIME = 2.0          -- "roar" clip (40 frames at 20 fps)

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local flat_dist, is_water, is_solid = kc.flat_dist, kc.is_water, kc.is_solid
local probe, play = kc.water_column, kc.play -- (column: floor and water surface; clip: locked)

local function point(self, p)
	return kc.model_point(self, p[1], p[2], p[3])
end

------------------------------------------------------------------------
-- Tentacle grab: an invisible grip the victim is attached to
------------------------------------------------------------------------

-- An attached object's server position is its parent's origin, whatever the attach offset.
-- So the victim hangs on a small entity of its own, which is dragged to the point in front
-- of his mouth: the victim's real position, its drowning and other mobs' aim follow.

-- Room for a victim (2 nodes tall) with its feet at p?
local function is_free(p)
	return not (is_solid(p) or is_solid(vector.offset(p, 0, 0.9, 0)) or is_solid(vector.offset(p, 0, 1.7, 0)))
end

-- Where the grip is dragged to: between his claws in the hold pose, but under water if
-- there is water at that spot. Never inside the ground: facing the shore his claws are in
-- the bank, so the point is pulled back towards him (2.5 forward is inside his own
-- collision box, where nothing solid can be) and, failing that, lifted out.
local function drag_point(self)
	local p
	for _, fwd in ipairs({HOLD[1], 4, 2.5}) do
		p = kc.model_point(self, fwd, HOLD[2], HOLD[3])
		if self._surface_y and p.y > self._surface_y - 2 then
			local low = vector.new(p.x, self._surface_y - 2, p.z)
			if is_water(low) then p = low end
		end
		if is_free(p) then return p end
	end
	local n = 0
	repeat p.y, n = p.y + 1, n + 1 until n >= 16 or is_free(p)
	return p
end

local function detach_victim(grip)
	local v = grip._victim
	grip._victim = nil
	if not (v and v:is_valid() and v:get_attach() == grip.object) then return end
	v:set_detach()
	local ent = v:get_luaentity()
	if ent then ent._fall_distance = 0 end
	-- released on dry land: put it down instead of dropping it or leaving it inside the
	-- ground (the grip passes through nodes)
	local p = v:get_pos()
	if not is_water(p) then
		local ground = kc.ground_y(vector.offset(p, 0, 3, 0))
		if is_solid(p) or p.y - ground > 1.5 then v:set_pos(vector.new(p.x, ground + 0.1, p.z)) end
	end
end

local function release(grip)
	detach_victim(grip)
	grip.object:remove()
end

core.register_entity("cthulhu:grip", {
	initial_properties = {
		visual = "sprite", textures = {"blank.png"}, physical = false, pointable = false,
		static_save = false, collisionbox = {0, 0, 0, 0, 0, 0},
	},
	on_activate = function(self)
		self.object:set_armor_groups({immortal = 1})
	end,
	on_step = function(self, dtime)
		local owner = self._owner and self._owner:is_valid() and self._owner:get_luaentity()
		local v = self._victim
		local vent = v and v:is_valid() and v:get_luaentity()
		self._age = (self._age or 0) + dtime
		if not owner or owner.dead or owner._grip ~= self.object or owner._fleeing or owner._returning
				or not (v and v:is_valid()) or v:get_hp() <= 0 or (vent and vent.dead)
				or v:get_attach() ~= self.object
				or self._age >= GRAB_HOLD or (owner._grab_damage or 0) >= GRAB_BREAK then
			release(self)
			return
		end
		local p, to = self.object:get_pos(), drag_point(owner)
		local d = vector.distance(p, to)
		if d > 0.05 then
			-- (move_to: clients interpolate, the victim doesn't jump)
			self.object:move_to(vector.add(p, vector.multiply(vector.subtract(to, p), math.min(1, DRAG_SPEED * dtime / d))), true)
		end
		self._squeeze = (self._squeeze or 1) - dtime
		if self._squeeze <= 0 then
			self._squeeze = 1
			mcl_util.deal_damage(v, SQUEEZE, {type = "mob", source = self._owner, direct = self._owner})
		end
	end,
	on_deactivate = detach_victim, -- unload (the engine detaches as well)
})

-- Players and small mobs, never kaiju or bosses. Riders are left alone, except the driver
-- of a boat: he is pulled out of it.
local function can_grab(self, obj)
	if not obj:is_valid() then return false end
	local ent = obj:get_luaentity()
	if obj:is_player() then
		if not self:attack_player_allowed(obj) then return false end
	elseif not (ent and ent.is_mob and not ent.dead and not ent.is_boss and not kc.is_kaiju(ent)) then
		return false
	else
		-- (VoxeLibre's mobs have no collisionbox field)
		local cb = ent.collisionbox or obj:get_properties().collisionbox
		if cb[5] - cb[2] >= 3 then return false end
	end
	local parent = obj:get_attach()
	if not parent then return true end
	local pent = parent:get_luaentity()
	return obj:is_player() and pent and pent.name:find("^mcl_boats:") and pent._driver == obj or false
end

local function end_grab(self)
	if not self._grab_t then return end
	if self._grip and self._grip:is_valid() then release(self._grip:get_luaentity()) end
	self._grab_t, self._grab_victim, self._grip, self._grip_made = nil, nil, nil, nil
	self._grab_cooldown = GRAB_COOLDOWN
	self._anim_lock = 0
	self.attacking = nil -- re-initialise the melee state machine
end

local function start_grab(self, target)
	self._grab_t, self._grab_victim, self._grab_damage = 0, target, 0
	self.attacking = nil
	if self._at_sea then
		self._goal = self.object:get_pos() -- stay put
	else
		self:cancel_navigation()
		self:halt_in_tracks(true)
	end
	-- the clip ends in the hold pose (frame 290) and stays there until the grab is over
	play(self, "grab", GRAB_HOLD + 2)
	self:mob_sound("attack")
end

local function grab_step(self, dtime)
	if not self._grab_t then return end
	self._grab_t = self._grab_t + dtime
	if self._grip_made then
		if not (self._grip and self._grip:is_valid()) then end_grab(self) end
	elseif self._grab_t >= GRAB_CLOSE then
		-- the claws close: is the victim still there?
		local v = self._grab_victim
		if not (v and can_grab(self, v) and vector.distance(point(self, FACE), v:get_pos()) <= GRAB_RANGE + 3) then
			end_grab(self)
			return
		end
		local parent = v:get_attach()
		if parent then
			v:set_detach() -- (the boat's on_detach_child tidies up; the boat stays)
			-- VoxeLibre's boats have no on_detach_child: tidy up for them
			local boat = parent:get_luaentity()
			if boat and boat._driver == v then
				boat._driver = nil
				v:set_properties({visual_size = {x = 1, y = 1, z = 1}})
				if mcl_player and mcl_player.player_attached then mcl_player.player_attached[v:get_player_name()] = false end
			end
		end
		local grip = core.add_entity(v:get_pos(), "cthulhu:grip")
		local ent = grip and grip:get_luaentity()
		if not ent then
			end_grab(self)
			return
		end
		ent._owner, ent._victim = self.object, v
		v:set_attach(grip, "", vector.zero(), vector.zero())
		-- top-level fields: mcl_mobs drops ObjectRefs from staticdata only there
		self._grip, self._grip_made = grip, true
	end
end

------------------------------------------------------------------------
-- Mob definition
------------------------------------------------------------------------

local cthulhu = {
	description = S("Cthulhu"),
	type = "monster",
	_spawn_category = "misc",
	persistent = true,
	hp_min = HP,
	hp_max = HP,
	xp_min = 250,
	xp_max = 250,
	-- 45: 550 HP are worth 1222 in water (Gojira 500/0.40 = 1250, Ghidorah 600/0.50 = 1200)
	-- and 815 on land, where he takes LAND_FACTOR
	armor = 45,
	collisionbox = {-2.8, 0, -2.8, 2.8, H, 2.8},
	head_eye_height = 9,
	doll_size_override = {x = 0.2, y = 0.2},
	visual = "mesh",
	mesh = "cthulhu.glb",
	textures = {{"cthulhu.png"}},
	visual_size = {x = SCALE, y = SCALE},
	glow = 5,                  -- a dim shape in the deep and in the darkness of his aura (which blacks out all else)
	makes_footstep_sound = true,
	stepheight = 1.1,
	movement_speed = 7.0,      -- a little slower than Gojira (7.5): he lumbers on land
	floats = 0,                -- never bobs on the surface: sea mode holds his depth
	damage = 16,               -- claw swipe, between Ghidorah's bite (10) and Gojira's (18): no ranged weapon
	reach = 8,                 -- long arms; measured from the centre (Gojira 7, Ghidorah 8)
	melee_interval = 1.5,
	attack_type = "null",
	view_range = 64,
	tracking_distance = 96,    -- (the leash ends a chase, not this)
	_no_fall_damage = true,
	_melee_esp = true,
	can_ride_boat = false,
	can_ride_cart = false,
	drops = {
		{name = "mcl_mobitems:heart_of_the_sea", chance = 1, min = 1, max = 1},
		{name = "mcl_ocean:prismarine_crystals", chance = 1, min = 8, max = 16, looting = "common"},
		{name = "mcl_mobitems:ink_sac", chance = 1, min = 4, max = 8, looting = "common"},
	},
	sounds = {
		random = {name = "mobs_mc_guardian_random", gain = 2.5},
		attack = {name = "mobs_mc_squid_flop", gain = 2.5},
		war_cry = {name = "mobs_mc_wither_spawn", gain = 2},
		damage = {name = "mobs_mc_guardian_hurt", gain = 2},
		death = {name = "mobs_mc_guardian_death", gain = 2.5},
		base_pitch = 0.4,
		distance = 96,
	},
	-- frame ranges match tools/cthulhu_model.py (glTF time in seconds, exported at 1 fps)
	animation = {
		stand_start = 0, stand_end = 60, stand_speed = 15,
		walk_start = 70, walk_end = 110, walk_speed = 40 / WALK_CYCLE_NODES,
		swim_start = 120, swim_end = 160, swim_speed = 16,
		rise_start = 170, rise_end = 230, rise_speed = 20, rise_loop = false,
		punch_start = 240, punch_end = 260, punch_speed = 25,
		grab_start = 270, grab_end = 290, grab_speed = 20, grab_loop = false,
		roar_start = 310, roar_end = 350, roar_speed = 20, roar_loop = false,
		die_start = 360, die_end = 400, die_speed = 10, die_loop = false,
		dormant_start = 410, dormant_end = 450, dormant_speed = 8,
	},
	_smash = {lookahead = 3},
}

kc.lock_animations(cthulhu) -- rise, roar and grab are one-shot clips

------------------------------------------------------------------------
-- Home and territory
------------------------------------------------------------------------

-- Home is where he sleeps and the centre of his territory. The egg can't be used on the
-- sea floor (it doesn't point through water), so he looks around the spot he was spawned
-- on, unless that spot is deep enough to submerge in: the nearest ring with such water
-- (so the beach he was spawned on stays in his territory), else the deepest he finds.
function cthulhu:on_spawn()
	local pos = self.object:get_pos()
	local best, best_depth = pos, 0
	local function try(x, z)
		local floor, surface = probe(vector.new(x, pos.y, z))
		local depth = surface and surface - floor or 0
		if depth >= SEA_ENTER and depth > best_depth then
			best, best_depth = vector.new(x, floor, z), depth
		end
	end
	try(pos.x, pos.z)
	for r = 4, TERRITORY, 4 do
		if best_depth >= HOME_DEPTH then break end
		for i = 0, 15 do
			try(pos.x + math.cos(i * math.pi / 8) * r, pos.z + math.sin(i * math.pi / 8) * r)
		end
	end
	-- a plain table: it is saved with the mob (vectors lose their metatable on reload)
	self._home = {x = best.x, y = best.y, z = best.z}
	self._home_depth = best_depth
end

-- Every targeting rule passes through here, for a new target and for the one he has:
-- nobody beyond the leash is chased, and kaiju on a truce retreat are left alone (hitting
-- one would end the truce), also one he was fighting when its retreat began.
function cthulhu:test_object_and_restriction(object, obj_pos)
	if self._home and flat_dist(obj_pos, self._home) > LEASH then return false end
	local ent = object:get_luaentity()
	if ent and ent._retreat_until then return false end
	return mob_class.test_object_and_restriction(self, object, obj_pos)
end

-- Under the open sky, or in water that is: the beach and the sea, not caves and cellars
-- (he senses intruders without seeing them, but not through the rock).
local function exposed(pos)
	local p, n = vector.round(vector.offset(pos, 0, 0.5, 0)), 0
	while n < 64 and is_water(p) do p.y, n = p.y + 1, n + 1 end
	return (core.get_natural_light(p, 0.5) or 0) >= OPEN_SKY
end

-- (mcl_mobs has no common flag for flyers; `airborne` is only the parrot's)
local FLYERS = {["mobs_mc:bat"] = true, ["mobs_mc:blaze"] = true, ["mobs_mc:vex"] = true, ["mobs_mc:ghast"] = true}

-- Players and land mobs on the beach or in the sea. Not fish and other water creatures,
-- not flyers, nobody under ground.
local function is_intruder(obj, pos)
	if not obj:is_player() then
		local ent = obj:get_luaentity()
		if not (ent and ent.is_mob and ent.name ~= "cthulhu:cthulhu"
				and not (ent.swims or ent.breathes_in_water or ent.amphibious)
				and not (ent.airborne or ent._flying or ent.name == "mothra:mothra" or FLYERS[ent.name])) then
			return false
		end
		if pos.y - kc.ground_y(pos) > FLYER_HEIGHT then return false end
	end
	return exposed(pos)
end

-- The nearest intruder in his territory. He senses them: no line of sight needed (from
-- the sea floor the shore is hidden behind the slope).
local intruder_rule = mcl_mobs.build_target_rule({fn = function(self, self_pos, dtime, obj, is_current)
	local home = self._home
	if not home then return nil end
	if is_current then
		return self:test_object_and_restriction(obj, obj:get_pos()) and obj or nil
	end
	if not self:check_timer("seek_target", 0.5) then return false end
	local best, best_d
	for o in core.objects_in_area(vector.new(home.x - TERRITORY, home.y - 16, home.z - TERRITORY),
			vector.new(home.x + TERRITORY, home.y + 80, home.z + TERRITORY)) do
		local p = o:get_pos()
		if o ~= self.object and o ~= self._ignored and flat_dist(p, home) <= TERRITORY
				and is_intruder(o, p) and self:test_object_and_restriction(o, p) then
			local d = vector.distance(self_pos, p)
			if not best_d or d < best_d then best, best_d = o, d end
		end
	end
	return best
end})

cthulhu._targeting_rules = {
	mcl_mobs.build_retaliation_target_rule({"cthulhu:cthulhu"}, false, nil), -- wherever the attacker stands (within the leash)
	intruder_rule,
}

-- No target while he dives away or walks home, and the one he gave up is forgotten: back
-- home he only takes up whoever is (still) in his territory or attacks him.
function cthulhu:get_active_target(self_pos)
	if self._fleeing or self._returning then
		self._active_target, self._active_targeting_rule = nil, nil
		return nil
	end
	return mob_class.get_active_target(self, self_pos)
end

-- Fully under water nobody can target him (mcl_mobs asks this for every mob's target),
-- unless he is attacking: whoever he fights can always fight back.
function cthulhu:valid_enemy()
	if self.attack or self._grab_t then return true end
	local pos = self.object:get_pos()
	return not (self._surface_y and pos and pos.y + H < self._surface_y)
end

------------------------------------------------------------------------
-- Sea mode
------------------------------------------------------------------------

local function set_sea(self, on)
	self._at_sea = on or nil
	self:cancel_navigation()
	kc.end_bulldoze(self)
	self._goal, self._floor, self._lift = nil, nil, nil
	self.attacking = nil
end

-- Set the swimming goal. Where the sea floor rises ahead he lifts over it first
-- (kaiju_core.fly_velocity climbs on the spot while he is below self._floor - 2).
local function swim_to(self, self_pos, goal, speed)
	if self._probed then
		self._probed = nil
		local d = vector.new(goal.x - self_pos.x, 0, goal.z - self_pos.z)
		local len = vector.length(d)
		local ahead = len > 0.5 and probe(vector.add(self_pos, vector.multiply(d, math.min(4, len) / len))) or self._floor_y
		self._lift = ahead > self._floor_y + 0.5 and ahead or nil
	end
	if self._lift then
		goal.y = math.max(goal.y, self._lift + 0.5)
		self._floor = self._lift + 2.5
	else
		self._floor = nil
	end
	self._goal, self._goal_speed = goal, speed
end

function cthulhu:motion_step(dtime, moveresult, self_pos)
	if not self._at_sea or self.dead then
		-- (dead: gravity takes him to the sea floor)
		return mob_class.motion_step(self, dtime, moveresult, self_pos)
	end
	local want = kc.fly_velocity(self, dtime, self_pos, SWIM_SPEED)
	if self.attack and self.attack:is_valid() then
		self:look_at(self.attack:get_pos())
	elseif want.x * want.x + want.z * want.z > 0.25 then
		self:set_yaw(math.atan2(want.z, want.x) - math.pi / 2)
	end
end

-- The target's collision box (get_properties copies every property: once per target).
local boxes = setmetatable({}, {__mode = "k"})
local function target_box(self)
	local c = boxes[self]
	if not c or c[1] ~= self.attack then
		c = {self.attack, self.attack:get_properties().collisionbox}
		boxes[self] = c
	end
	return c[2]
end

-- Swim towards the target: head and shoulders out of the water for one at the surface
-- (swimmers included: its top counts, not its feet), level with one under water, never
-- closer than the melee standoff.
local function swim_at(self, self_pos, target_pos)
	local tcb = target_box(self)
	local gap = kc.standoff_gap(self, tcb)
	local d = flat_dist(self_pos, target_pos)
	local k = d > gap and (d - gap) / d or 0
	local floor, surface = self._floor_y or self_pos.y, self._surface_y
	local y = self_pos.y
	if surface then
		y = surface - (H - HEAD_OUT)
		-- (in water: a target in a dry pit below sea level, e.g. the one he dug, is not)
		if target_pos.y + tcb[5] < surface - 2 and is_water(vector.offset(target_pos, 0, tcb[5], 0)) then
			y = math.min(y, target_pos.y - H / 2)
		end
	end
	swim_to(self, self_pos, vector.new(self_pos.x + (target_pos.x - self_pos.x) * k, math.max(y, floor),
		self_pos.z + (target_pos.z - self_pos.z) * k), SWIM_SPEED)
	return d
end

-- Home: cruise there submerged, then settle on the sea floor in the idol pose.
local function swim_home(self, self_pos, grounded)
	local home = self._home or self_pos
	local floor = self._floor_y or self_pos.y
	if flat_dist(self_pos, home) > HOME_RADIUS then
		local y = self._surface_y and math.max(floor, self._surface_y - H - 2) or self_pos.y
		swim_to(self, self_pos, vector.new(home.x, y, home.z), CRUISE_SPEED)
		self:set_animation("swim")
	else
		self._returning = nil
		swim_to(self, self_pos, vector.new(self_pos.x, floor, self_pos.z), CRUISE_SPEED)
		-- (on a slope he rests on the highest node under him, above the centre column's floor)
		self:set_animation((grounded or self_pos.y - floor < 1.6) and "dormant" or "swim")
	end
end

-- The same on foot (an ai_function): walk straight home like a bulldoze, then rest.
local function walk_home(self, self_pos, dtime)
	local home = self._home
	if home and flat_dist(self_pos, home) > HOME_RADIUS then
		-- (navigation_step follows a pathfinder path before the straight-line goal)
		if self.waypoints or self.pathfinding_context then self:cancel_navigation() end
		self:go_to_stupidly(vector.new(home.x, self_pos.y, home.z), 1)
		self:set_animation("walk")
	else
		self._returning = nil
		if self:is_navigating() then
			self:cancel_navigation()
			self:halt_in_tracks()
		end
		self:set_animation("dormant")
	end
	return true
end

------------------------------------------------------------------------
-- Fighting
------------------------------------------------------------------------

function cthulhu:attack_null(attach_pos, self_pos, dtime, target_pos, line_of_sight)
	local sea = self._at_sea
	-- (not while he holds a victim: it hangs under water, and he would dive after it)
	local dist = sea and not self._grab_t and swim_at(self, self_pos, target_pos)
	if not self._engaged then
		self._engaged = true
		if self._current_animation == "dormant" then
			play(self, "rise", RISE_TIME)
			self._roar_timer = 0 -- he wakes with a roar
		end
	end
	if self._grab_t or (self._anim_lock or 0) > 0 then return end
	if (self._roar_timer or 0) <= 0 then
		self._roar_timer = ROAR_INTERVAL
		self.attacking = nil
		if not sea then
			self:cancel_navigation()
			self:halt_in_tracks(true)
		end
		self:look_at(target_pos)
		play(self, "roar", ROAR_TIME)
		self:mob_sound("war_cry")
		return
	end
	if (self._grab_cooldown or 0) <= 0 and line_of_sight and can_grab(self, self.attack)
			and vector.distance(point(self, FACE), target_pos) <= GRAB_RANGE then
		start_grab(self, self.attack)
		return
	end
	if not sea then kc.update_bulldoze(self, dtime, attach_pos, target_pos) end
	mob_class.attack_melee(self, attach_pos, self_pos, dtime, target_pos, line_of_sight)
	if sea then self:set_animation(dist > 16 and "swim" or "stand") end
end

-- In sea mode his feet are 9 nodes below the surface: reach counts from the nearest point
-- of his body's axis instead (on land from his feet, as kaiju_core's standoff expects).
local function attack_dist(self, p, t)
	return kc.axis_dist(p, t, self._at_sea and H or 0)
end

function cthulhu:pre_melee_attack(distance, delay, line_of_sight)
	local t = self._at_sea and self.attack and self.attack:get_pos()
	if t then distance = attack_dist(self, self.object:get_pos(), t) end
	return mob_class.pre_melee_attack(self, distance, delay, line_of_sight)
end

function cthulhu:gopath(...)
	if self._at_sea then return true end -- (swim_at steers)
	return kc.gopath(self, ...)
end

function cthulhu:attack_end()
	end_grab(self)
	self._engaged, self._stall_best, self._stall_time = nil, nil, nil
	kc.end_bulldoze(self)
	return mob_class.attack_end(self)
end

------------------------------------------------------------------------
-- Every step
------------------------------------------------------------------------

local function start_return(self)
	self._returning = true
	self._return_time = RETURN_TIMEOUT
	self._return_attack_id = self._last_attack_id
	self._land_time = 0
end

local function tick(self, self_pos, dtime)
	if self._anim_lock then self._anim_lock = self._anim_lock - dtime end
	self._roar_timer = math.max((self._roar_timer or 0) - dtime, 0)
	self._grab_cooldown = math.max((self._grab_cooldown or 0) - dtime, 0)
	local depth = self._immersion_depth or 0

	self._probe_timer = (self._probe_timer or 0) - dtime
	if self._probe_timer <= 0 or not self._floor_y then
		self._probe_timer = 0.5
		self._floor_y, self._surface_y = probe(self_pos)
		self._probed = true
	end
	if not self._at_sea and depth >= SEA_ENTER then
		set_sea(self, true)
	elseif self._at_sea and depth < SEA_LEAVE then
		set_sea(self, false)
	end

	-- regeneration: at least half submerged and 5 s (mcl_mobs' _recent_attacker) after a hit
	if depth >= H / 2 and not self._recent_attacker and self.health < HP then
		self:heal_mob(REGEN * dtime, HP)
	end
	-- badly hurt he dives away, if home is deep enough to hide in. Not for ever: if he
	-- can't get there or can't heal there, he comes back and fights it out (_cornered).
	local low = self.health < FLEE_BELOW * HP
	if self._fleeing then
		self._flee_time = (self._flee_time or 0) + dtime
		if self.health >= FLEE_UNTIL * HP or self._flee_time > FLEE_TIMEOUT then
			self._fleeing, self._flee_time, self._cornered = nil, nil, low or nil
		end
	elseif not low then
		self._cornered = nil
	elseif not self._cornered and (self._home_depth or 0) > H then
		self._fleeing = true
	end
	if self._ignored then
		self._ignore_time = (self._ignore_time or 0) - dtime
		if self._ignore_time <= 0 or not self._ignored:is_valid() then self._ignored = nil end
	end

	local home = self._home
	if self._returning then
		self._return_time = (self._return_time or 0) - dtime
		local id, by = self._last_attack_id, self._last_attacker
		if self._return_time <= 0 then
			self._returning = nil
		elseif id ~= self._return_attack_id then
			-- hit on the way home: he turns on the attacker (if within the leash)
			self._return_attack_id = id
			if by and by:is_valid() and self:test_object_and_restriction(by, by:get_pos()) then
				self._returning = nil
			end
		end
	elseif self.attack then
		self._land_time = depth < 1 and (self._land_time or 0) + dtime or 0
		-- no progress: the target is out of reach and he got no closer (wherever he stands)
		local t = self.attack:is_valid() and self.attack:get_pos()
		local d = t and attack_dist(self, self_pos, t) or 0
		if self._grab_t or d <= self.reach + 1 or d < (self._stall_best or math.huge) - 1 then
			self._stall_best, self._stall_time = d, 0
		else
			self._stall_time = (self._stall_time or 0) + dtime
		end
		if self._stall_time > STALL_LIMIT then
			-- (a top-level field: mcl_mobs drops ObjectRefs from the staticdata there)
			self._ignored, self._ignore_time = self.attack, IGNORE_TIME
			start_return(self)
		elseif self._land_time > LAND_LIMIT or (home and flat_dist(self_pos, home) > LEASH + 8) then
			start_return(self)
		end
	else
		self._land_time = 0
	end

	grab_step(self, dtime)
end

function cthulhu:run_ai(dtime, moveresult)
	if self.dead then return mob_class.run_ai(self, dtime, moveresult) end
	local self_pos = self.object:get_pos()
	tick(self, self_pos, dtime)
	if not self._at_sea then
		return mob_class.run_ai(self, dtime, moveresult)
	end
	if self:check_attack(self_pos, dtime) then return end
	self.attacking = nil
	swim_home(self, self_pos, moveresult and moveresult.touching_ground)
end

cthulhu.ai_functions = {
	mob_class.check_attack,
	walk_home,
}

-- Head and hump carry hit boxes (kaiju_core.ensure_hitboxes): arrows only find objects
-- whose position is within 5 nodes of their path, and his position is at his feet.
-- shortcut: stand-pose positions; off in dormant, swim and roar. Per-animation offsets if that matters.
local HITBOXES = {
	{name = "chest", pos = function(self) return kc.model_point(self, 0.5, 0, 9) end, box = {-3, -3.5, -3, 3, 3.5, 3}},
	{name = "head", pos = function(self) return kc.model_point(self, 4.2, 0, 7.5) end, box = {-2.2, -2.2, -2.2, 2.2, 2.2, 2.2}},
}

-- The madness: players near him while he fights see the colours turn (nausea) and, up
-- close, the dark close in. Both run out a few seconds after they get away.
local function aura(self)
	local head = vector.offset(self.object:get_pos(), 0, 8, 0)
	for _, player in ipairs(core.get_connected_players()) do
		local d = vector.distance(player:get_pos(), head)
		if d <= AURA_RADIUS and self:attack_player_allowed(player) then
			mcl_potions.give_effect_by_level("nausea", player, 1, 3, true)
			-- (every refresh restarts the darkness pulse: only when it is nearly over)
			local dark = d <= DARK_RADIUS and mcl_potions.get_effect(player, "darkness")
			if d <= DARK_RADIUS and not (dark and dark.dur - dark.timer > 1.5) then
				mcl_potions.give_effect_by_level("darkness", player, 1, 5, true)
			end
		end
	end
end

function cthulhu:ai_step(dtime)
	mob_class.ai_step(self, dtime)
	if self.dead then return end
	kc.ensure_hitboxes(self, HITBOXES)
	-- (not while he rests at home: he would wear the sea floor away under him)
	local home = self._home
	if self.attack or not home or flat_dist(self.object:get_pos(), home) > HOME_RADIUS then
		kc.smash_step(self, dtime, "cthulhu:cthulhu")
	end
	self._aura_timer = (self._aura_timer or 0) - dtime
	if self._aura_timer <= 0 and (self.attack or self._grab_t) then
		self._aura_timer = 1
		aura(self)
	end
end

------------------------------------------------------------------------
-- Water, damage, death
------------------------------------------------------------------------

-- Always "wading" for mcl_mobs (no swim physics, no bobbing); the real depth is returned
-- and drives sea mode, regeneration and the land weakness.
function cthulhu:check_standin(dtime, attach_pos)
	return kc.check_standin(self, dtime, attach_pos, math.huge)
end

function cthulhu:step_drowning()
	return false
end

function cthulhu:receive_damage(reason, damage)
	if damage > 0 then
		if (self._immersion_depth or 0) < 1 then damage = damage * LAND_FACTOR end
		if self._grab_t then self._grab_damage = (self._grab_damage or 0) + damage end
	end
	return mob_class.receive_damage(self, reason, damage)
end

function cthulhu:check_for_death(reason, damage)
	local died = kc.check_for_death(self, reason, damage)
	if self.dead then end_grab(self) end
	return died
end

cthulhu.gwp_penalties = table.copy(mob_class.gwp_penalties)
cthulhu.gwp_penalties.WATER = 0.0

kc.no_knockback(cthulhu)
mcl_mobs.register_mob("cthulhu:cthulhu", cthulhu)

-- Egg only: no natural spawner is registered.
mcl_mobs.register_egg("cthulhu:cthulhu", S("Cthulhu"), "#162622", "#80B27C", 0)
