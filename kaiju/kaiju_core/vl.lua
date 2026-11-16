-- VoxeLibre support. init.lua loads this file only when the game's mcl_mobs is VoxeLibre's
-- (the older API, without Mineclonia's AI hooks). It provides, as kaiju_core.mcl_mobs, the
-- part of Mineclonia's mob API the kaiju are written against: a mob class whose on_step
-- runs the hooks in Mineclonia's order (check_standin, navigation, motion_step, ai_step,
-- targeting rules, run_ai), melee, the target rule builders, damage and death. It is an
-- own, much smaller implementation (README.md §VoxeLibre): a pathfinder of its own
-- (vl_path.lua), no environment damage except burning, no fall damage.

local VL = mcl_mobs.mob_class
local K = setmetatable({}, {__index = VL})
local api = setmetatable({mob_class = K}, {__index = mcl_mobs})
kaiju_core.mcl_mobs = api

-- mobs_griefing is a plain setting on VoxeLibre (Mineclonia: a gamerule per mob)
function kaiju_core.mob_griefing() return core.settings:get_bool("mobs_griefing", true) end
-- (read once at load, as VoxeLibre's own digs do: mcl_item_entity)
local TILE_DROPS = core.settings:get_bool("mcl_doTileDrops", true)
function kaiju_core.tile_drops() return TILE_DROPS end

-- VoxeLibre's natural stone has no terrain group (Mineclonia: overworld_carvable), so a
-- kaiju would cut the foot-level steps it climbs on and tunnel instead. The same nodes by
-- name (not VoxeLibre's `stone` group: that includes stone bricks).
core.register_on_mods_loaded(function()
	local carvable = {}
	for _, n in ipairs({"mcl_core:stone", "mcl_core:granite", "mcl_core:andesite", "mcl_core:diorite",
			"mcl_deepslate:deepslate", "mcl_deepslate:tuff", "mcl_mud:mud", "mcl_mangrove:mangrove_mud_roots"}) do
		carvable[n] = core.registered_nodes[n] ~= nil
	end
	local is_terrain = kaiju_core.is_terrain
	function kaiju_core.is_terrain(name) return carvable[name] or is_terrain(name) end
	-- The pathfinder needs each kaiju's swim depth, which the mods pass only here.
	-- (not math.huge: VoxeLibre serialises the entity's fields)
	local check_standin = kaiju_core.check_standin
	function kaiju_core.check_standin(self, dtime, attach_pos, swim_depth)
		self._swim_depth = swim_depth < math.huge and swim_depth or nil
		return check_standin(self, dtime, attach_pos, swim_depth)
	end
end)

dofile(core.get_modpath("kaiju_core") .. "/vl_path.lua")

local SPEED = 0.8          -- nodes/s per movement_speed unit (Gojira 7.5: ~6 n/s, as on Mineclonia)
local SWIM_SPEED = 5 / 3   -- nodes/s per water_velocity unit (Gojira 3.0: ~5 n/s)
local GRAVITY = 14.7       -- VoxeLibre's mob fall acceleration
local JUMP = 7             -- jump velocity against a wall it can't step onto (~1.6 nodes)
local RISE = 4             -- vertical speed in water (floats == 1 rises, else sinks)
local TURN_RATE = 5        -- rad/s
local SEEK_INTERVAL = 0.5  -- nearest-target rules look for a new target this often
local SIGHT_PERSISTENCE = 3
local RETALIATION_PERSISTENCE = 15
local PUSH = 3             -- nodes/s away from a mob it overlaps
local PACE_TIMEOUT = 15    -- a pace towards a spot it can't reach ends after this
local ARRIVE = 0.6         -- nodes from a waypoint at which the next one is taken

-- Defaults of Mineclonia's mob class that the kaiju rely on (their definitions override them).
K.gwp_penalties = {}
K.movement_speed = 14
K.pursuit_bonus = 1
K.pace_bonus = 1
K.pace_chance = 120
K.pace_interval = 5
K.pace_width = 10
K.tracking_distance = 16
K.melee_interval = 1
K.water_velocity = 1
K.ai_idle_time = 0

local function mob_alive(ent)
	return not (ent.dead or ent.state == "die") and (ent.health or 1) > 0
end

local NO_MOVE = {touching_ground = false, collides = false, standing_on_object = false, collisions = {}}

------------------------------------------------------------------------
-- Timers, sounds, animation, rotation
------------------------------------------------------------------------

function K:post_load_staticdata()
	self._timers, self._timers_fired = {}, {}
	-- activities and targets are not carried over a reload
	self._active_activity, self._active_activity_function, self._can_interrupt_activity = nil, nil, nil
	self.pacing, self.attacking, self.attack = nil, nil, nil
	self.waypoints, self._nav_partial, self._wp_from = nil, nil, nil
	-- (the attack counter restarts at 0: an old id would match a new attack)
	self._last_attack_id, self._last_recorded_attack_id = nil, nil
end

function K:update_timers(dtime)
	for k, v in pairs(self._timers) do
		self._timers[k] = v - dtime
		self._timers_fired[k] = nil
	end
end

-- True once every `interval` seconds (and for the rest of the step it fired in).
function K:check_timer(name, interval)
	local t = self._timers
	if not t[name] then t[name] = math.random() * interval end
	if t[name] <= 0 then
		t[name] = interval
		self._timers_fired[name] = true
		return true
	end
	return self._timers_fired[name] or false
end

function K:mob_sound(name)
	local sounds = self.sounds
	local sound = sounds and sounds[name]
	if not sound then return end
	core.sound_play(sound, {object = self.object, max_hear_distance = sounds.distance,
		pitch = (sounds.base_pitch or 1) + math.random(-10, 10) * 0.005}, true)
end

-- Mineclonia's rules: a dead mob only plays die (or stand), and a melee punch whose clip
-- is still running turns any other clip into "punch".
function K:set_animation(anim, fixed_frame)
	local a = self.animation
	if not a or not anim then return end
	if self.dead and anim ~= "die" and anim ~= "stand" then return end
	if self.attack and (self._punch_animation_timeout or 0) > 0 then anim = "punch" end
	if (anim == self._current_animation or not a[anim .. "_start"] or not a[anim .. "_end"]) and not self.dead then
		return
	end
	self._current_animation = anim
	local first = a[anim .. "_start"]
	self.object:set_animation({x = first, y = fixed_frame and first or a[anim .. "_end"]},
		a[anim .. "_speed"] or a.speed_normal or 15, 0, a[anim .. "_loop"] ~= false)
	self._anim_fps = nil
end

-- walk plays at walk_speed frames per node (the feet stay planted), the rest at their speed.
function K:set_animation_speed()
	local anim = self._current_animation
	if not anim then return end
	local fps = self.animation[anim .. "_speed"] or self.animation.speed_normal or 25
	if anim == "walk" then
		local v = self.object:get_velocity()
		fps = fps * math.sqrt(v.x * v.x + v.z * v.z)
	end
	-- (each call is a packet to every client)
	if not self._anim_fps or math.abs(fps - self._anim_fps) > 0.5 then
		self._anim_fps = fps
		self.object:set_animation_frame_speed(fps)
	end
end

function K:set_yaw(yaw)
	self._target_yaw = yaw
	return yaw
end

function K:look_at(p)
	local s = self.object:get_pos()
	self:set_yaw(math.atan2(p.z - s.z, p.x - s.x) - math.pi / 2)
end

-- Turn towards the yaw set_yaw asked for, at TURN_RATE.
function K:rotate_step(dtime)
	local want = self._target_yaw
	if not want then return end
	local yaw = self.object:get_yaw()
	local diff = (want - yaw + math.pi) % (2 * math.pi) - math.pi
	local max = TURN_RATE * dtime
	if math.abs(diff) <= max then
		self._target_yaw = nil
		self.object:set_yaw(want)
	else
		self.object:set_yaw(yaw + (diff > 0 and max or -max))
	end
end

------------------------------------------------------------------------
-- Navigation (paths from vl_path.lua, or a straight line) and motion
------------------------------------------------------------------------

function K:go_to_stupidly(pos, factor)
	self.stupid_target = pos
	self.stupid_velocity = self.movement_speed * (factor or 1)
end

-- Plans a path towards target (as far as the search window reaches). false: there is none.
function K:gopath(target, speed_bonus)
	local path, partial = kaiju_core.vl_find_path(self, target)
	if not path then
		self:cancel_navigation()
		return false
	end
	self.waypoints, self._nav_partial, self._wp_from = path, partial, self.object:get_pos()
	self.stupid_target = nil
	self.gowp_velocity = self.movement_speed * (speed_bonus or 1)
	return true
end

function K:cancel_navigation()
	self.waypoints, self._nav_partial, self._wp_from = nil, nil, nil
	self.stupid_target, self.movement_goal = nil, nil
end

function K:is_navigating()
	return self.waypoints or self.stupid_target
end

function K:navigation_finished()
	if self.waypoints then return false end
	local t = self.stupid_target
	if not t then return true end
	if kaiju_core.flat_dist(self.object:get_pos(), t) > 0.5 then return false end
	self:cancel_navigation()
	return true
end

function K:go_to_pos(pos, velocity, animation)
	self.movement_goal, self.movement_target = "go_pos", pos
	self.movement_velocity = velocity or self.movement_speed
	self:set_animation(animation or "walk")
end

-- Follows the path (waypoints, the next one last) before a straight-line goal, as on
-- Mineclonia. A waypoint is done within ARRIVE of it, or once the mob is past it.
function K:navigation_step()
	local wps = self.waypoints
	if not wps then
		if self.stupid_target then self:go_to_pos(self.stupid_target, self.stupid_velocity) end
		return
	end
	local pos, from = self.object:get_pos(), self._wp_from
	local wp = wps[#wps]
	while wp and (kaiju_core.flat_dist(pos, wp) <= ARRIVE
			or (wp.x - pos.x) * (wp.x - from.x) + (wp.z - pos.z) * (wp.z - from.z) <= 0) do
		from, wps[#wps] = wp, nil
		wp = wps[#wps]
	end
	self._wp_from = from
	if wp then
		self:go_to_pos(wp, self.gowp_velocity)
	else
		-- The end of a partial path is not the target: melee plans the next stretch at once.
		if self._nav_partial then self._target_pos = nil end
		self:cancel_navigation()
		self:halt_in_tracks()
	end
end

function K:halt_in_tracks(immediate, keep_animation)
	self.movement_goal = nil
	if not keep_animation and (self._current_animation == "walk" or self._current_animation == "run") then
		self:set_animation("stand")
	end
	if immediate then self.object:set_velocity(vector.zero()) end
end

-- Water from the feet up: (depth of the water above the feet, "water" or nil).
function K:check_standin(dtime, pos)
	local cb = self.collisionbox
	local feet = pos.y + cb[2]
	local p = vector.new(math.floor(pos.x + 0.5), math.floor(feet + 0.5), math.floor(pos.z + 0.5))
	if not kaiju_core.is_water(p) then
		-- (kaiju_core.check_standin sets floats only in water: it must not stay 1 on land,
		-- where smash would keep cutting the foot layer)
		self.floats = 0
		return 0, nil
	end
	local top = feet + cb[5] - cb[2] + 2
	repeat p.y = p.y + 1 until p.y > top or not kaiju_core.is_water(p)
	return p.y - 0.5 - feet, "water"
end

-- Away from other kaiju whose collision boxes overlap its own, at PUSH (VoxeLibre's mobs
-- don't collide with objects: two kaiju would stay inside each other). Small mobs don't push.
local function push(self, pos)
	if self.pushable == false then return 0, 0 end
	local cb, x, z = self.collisionbox, 0, 0
	for obj in core.objects_inside_radius(pos, cb[4] - cb[1] + 1) do
		local ent = obj ~= self.object and obj:get_luaentity() or nil
		if kaiju_core.is_kaiju(ent) and ent.pushable ~= false and not ent.dead then
			local p, ob = obj:get_pos(), ent.collisionbox
			local dx, dz = pos.x - p.x, pos.z - p.z
			if dx + cb[1] < ob[4] and dx + cb[4] > ob[1] and dz + cb[3] < ob[6] and dz + cb[6] > ob[3]
					and pos.y + cb[2] < p.y + ob[5] and pos.y + cb[5] > p.y + ob[2] then
				local d = math.sqrt(dx * dx + dz * dz)
				if d < 0.01 then dx, dz, d = 1, 0, 1 end
				x, z = x + dx / d * PUSH, z + dz / d * PUSH
			end
		end
	end
	return x, z
end

local function blocked(moveresult)
	for _, c in ipairs(moveresult.collisions) do
		if c.type == "node" and c.axis ~= "y" then return true end
	end
	return false
end

-- Walking physics: towards movement_target at movement_velocity, gravity, buoyancy in
-- water for floats == 1 (check_standin decides), a jump against a wall.
function K:motion_step(dtime, moveresult, pos)
	local v = self.object:get_velocity()
	local swim = self._liquidtype == "water"
	local wx, wz = 0, 0
	local t = not self.dead and self.movement_goal == "go_pos" and self.movement_target
	if t then
		local dx, dz = t.x - pos.x, t.z - pos.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 0.1 then
			self:look_at(t)
			local speed = swim and self.water_velocity * SWIM_SPEED or self.movement_velocity * SPEED
			speed = math.min(speed, d / math.max(dtime, 0.05))
			wx, wz = dx / d * speed, dz / d * speed
			if moveresult.touching_ground and blocked(moveresult) then v.y = JUMP end
		end
	end
	local px, pz = push(self, pos)
	wx, wz = wx + px, wz + pz
	local k = math.min(1, dtime * ((moveresult.touching_ground or swim) and 10 or 2))
	v.x, v.z = v.x + (wx - v.x) * k, v.z + (wz - v.z) * k
	-- water brakes a fall at once (also while wading); swimming, floats == 1 rises and
	-- anything else sinks slowly
	local brake = math.min(1, dtime * 5)
	if swim then
		v.y = v.y + ((self.floats == 1 and RISE or -RISE) - v.y) * brake
	else
		v.y = v.y - GRAVITY * dtime
		if (self._immersion_depth or 0) > 0 and v.y < -RISE then v.y = v.y + (-RISE - v.y) * brake end
	end
	self.object:set_velocity(v)
end

------------------------------------------------------------------------
-- Sight and targets
------------------------------------------------------------------------

local function eye_of(obj)
	local p = obj:get_pos()
	if obj:is_player() then return vector.offset(p, 0, obj:get_properties().eye_height or 1.5, 0) end
	local ent = obj:get_luaentity()
	if ent and ent._kaiju_eye then return vector.offset(p, 0, ent._kaiju_eye, 0) end
	local cb = ent and ent.collisionbox or obj:get_properties().collisionbox
	return vector.offset(p, 0, (cb[5] - cb[2]) * 0.75 + cb[2], 0)
end

-- Nothing walkable between a and b (water, plants and the like don't block).
local function line_of_sight(a, b)
	for pointed in core.raycast(a, b, false, false) do
		if pointed.type == "node" then
			local def = core.registered_nodes[core.get_node(pointed.under).name]
			if not def or def.walkable then return false end
		end
	end
	return true
end
K.line_of_sight = function(_, a, b) return line_of_sight(a, b) end

-- From its eye to the target's (cached for the step).
function K:target_visible(self_pos, target)
	local seen = self._targets_visible[target]
	if seen == nil then
		seen = line_of_sight(vector.offset(self_pos, 0, self.head_eye_height, 0), eye_of(target))
		self._targets_visible[target] = seen
	end
	return seen
end

function K:attack_player_allowed(player)
	return not core.is_creative_enabled(player:get_player_name()) and player:get_hp() > 0
		and not core.settings:get_bool("only_peaceful_mobs", false)
end

function K:valid_enemy() return true end

function K:test_object_and_restriction(obj, pos)
	if obj:is_player() then return self:attack_player_allowed(obj) end
	local ent = obj:get_luaentity()
	if not (ent and mob_alive(ent)) then return false end
	return not ent.valid_enemy or ent:valid_enemy()
end

local function targetable(obj)
	if not obj:is_valid() then return false end
	if obj:is_player() then return true end
	local ent = obj:get_luaentity()
	return ent and ent.is_mob or false
end

local function dist2(a, b)
	return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2
end

function K:objects_for_targeting(pos, range)
	local list = self._object_search_lists[range]
	if not list then
		local cb = self.collisionbox
		list = core.get_objects_in_area(vector.offset(pos, cb[1] - range, cb[2] - range, cb[3] - range),
			vector.offset(pos, cb[4] + range, cb[5] + range, cb[6] + range))
		self._object_search_lists[range] = list
	end
	return list
end

local on_complete = {} -- targeting rule -> callback when it stops supplying the target

function api.build_target_rule(rule)
	on_complete[rule.fn] = rule.on_complete
	return rule.fn
end

-- The current target is kept while it is within max_d2 (squared) and, with persistence,
-- not out of sight for longer than that many seconds.
function K:track_current_target(self_pos, dtime, obj, max_d2, persistence)
	local p = obj:get_pos()
	if dist2(self_pos, p) > max_d2 or not self:test_object_and_restriction(obj, p) then return nil end
	if persistence then
		if self:target_visible(self_pos, obj) then
			self.target_invisible_time = persistence
		else
			local t = self.target_invisible_time or persistence
			self.target_invisible_time = t - dtime
			if t < 0 then return nil end
		end
	end
	return obj
end

local function name_predicate(names)
	return function(_, _, obj, ent)
		for _, n in ipairs(names) do
			if n == "player" and not ent or n == "monster" and ent and ent.type == "monster"
					or ent and ent.name == n then
				return true
			end
		end
		return false
	end
end

-- The nearest object in sight (base_type "player": players only) that passes predicate (a
-- function or a list of names), within range(view_range) or view_range. esp: no sight
-- needed to keep it (a number: seconds out of sight before it is let go).
function api.build_nearest_target_rule(base_type, predicate, start_predicate, range, esp)
	if type(predicate) == "table" then predicate = name_predicate(predicate) end
	predicate = predicate or function() return true end
	local persistence = type(esp) == "number" and esp or (not esp and SIGHT_PERSISTENCE or nil)
	local range_of = type(range) == "function" and range or function(r) return r end
	return api.build_target_rule({fn = function(self, self_pos, dtime, obj, is_current)
		if start_predicate and not start_predicate(self, self_pos) then return nil end
		if is_current then
			local d = range_of(self.tracking_distance)
			return self:track_current_target(self_pos, dtime, obj, d * d, persistence)
		end
		if not self:check_timer("seek_target", SEEK_INTERVAL) then return false end
		local r = range_of(self.view_range)
		local candidates = {}
		if base_type == "player" then
			candidates = core.get_connected_players()
		else
			candidates = self:objects_for_targeting(self_pos, r)
		end
		local best, best_d = nil, r * r
		for _, o in ipairs(candidates) do
			if o ~= self.object and targetable(o) then
				local p = o:get_pos()
				local d = dist2(self_pos, p)
				if d <= best_d and predicate(self, self_pos, o, o:get_luaentity())
						and self:target_visible(self_pos, o) and self:test_object_and_restriction(o, p) then
					best, best_d = o, d
				end
			end
		end
		return best
	end})
end

-- Whoever hurt it last (not those `ignore` matches), kept with RETALIATION_PERSISTENCE.
-- (alert_others is not supported: no kaiju uses it.)
function api.build_retaliation_target_rule(ignore)
	if type(ignore) == "table" then ignore = name_predicate(ignore) end
	return api.build_target_rule({fn = function(self, self_pos, dtime, obj, is_current)
		if is_current then
			return self:track_current_target(self_pos, dtime, obj, self.tracking_distance ^ 2, RETALIATION_PERSISTENCE)
		end
		local id = self._last_attack_id
		if self._last_recorded_attack_id == id then return nil end
		self._last_recorded_attack_id = id
		local by = self._last_attacker
		if not (by and targetable(by)) or (ignore and ignore(self, self_pos, by, by:get_luaentity())) then return nil end
		local p = by:get_pos()
		if self:test_object_and_restriction(by, p) and vector.distance(self_pos, p) < self.tracking_distance then
			return by
		end
	end})
end

-- Mineclonia's mobs alert others of their kind; VoxeLibre's don't send such alerts.
function api.build_alert_receiver_rule()
	return function() return nil end
end

function K:get_active_target() return self._active_target end

-- The first rule that yields a target wins; it is told (is_current) when it supplied the
-- current one.
function K:run_targeting_rules(dtime, self_pos)
	local rule, obj = self._active_targeting_rule, self._active_target
	if obj and not obj:is_valid() then rule, obj = nil, nil end
	self._active_targeting_rule, self._active_target, self._object_search_lists = nil, nil, {}
	for _, fn in ipairs(self._targeting_rules or {}) do
		local t = fn(self, self_pos, dtime, obj, rule == fn)
		if t and t:is_valid() and t ~= self.object and not self.dead then
			self._active_targeting_rule, self._active_target = fn, t
			break
		end
	end
	if obj ~= self._active_target then
		if self._active_targeting_rule then self.target_invisible_time = nil end
		local done = rule and on_complete[rule]
		if done then done(self, rule, self._active_targeting_rule) end
	end
end

------------------------------------------------------------------------
-- Fighting
------------------------------------------------------------------------

function K:attack_end() end

-- Start (returns "attack"), continue or end the attack on the active target.
function K:check_attack(self_pos, dtime)
	if not self.attack_type then return false end
	if not self.attack then
		local t = self:get_active_target(self_pos)
		if not t then return false end
		self.attack, self.attacking = t, false
		return "attack"
	end
	if not self.attack:is_valid() or self:get_active_target(self_pos) ~= self.attack then
		self.attack = nil
		self:attack_end()
		return true
	end
	local tp = self.attack:get_pos()
	local los = self:target_visible(self_pos, self.attack)
	if self.attack_type == "melee" then
		self:attack_melee(self_pos, self_pos, dtime, tp, los)
	elseif self.attack_type == "null" and self.attack_null then
		self:attack_null(self_pos, self_pos, dtime, tp, los)
	end
	return true
end

function K:pre_melee_attack(distance, delay, line_of_sight)
	return distance <= self.reach and delay == 0 and line_of_sight
end

function K:custom_attack()
	local a = self.animation
	if a.punch_start then
		self:set_animation("punch")
		self._punch_animation_timeout = (a.punch_end - a.punch_start) / (a.punch_speed or a.speed_normal or 25) - 0.09
	end
	self:mob_sound("attack")
	self.attack:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = self.damage}}, nil)
end

-- Walk at the target (a new path when it has moved a node, and now and then anyway, as
-- Mineclonia's melee) and bite every melee_interval while it is in reach and in sight.
function K:attack_melee(attach_pos, self_pos, dtime, target_pos, line_of_sight)
	local first = not self.attacking
	if first then
		self.attacking = true
		self._target_pos, self._gopath_delay, self._attack_delay = nil, 0, 0
		self._punch_animation_timeout = 0
	end
	if self._punch_animation_timeout then
		self._punch_animation_timeout = math.max(self._punch_animation_timeout - dtime, 0)
		if self._punch_animation_timeout == 0 then
			self._punch_animation_timeout = nil
			self:set_animation(self:navigation_finished() and "stand" or "walk")
		end
	end
	local delay = math.max(self._gopath_delay - dtime, 0)
	if (self._melee_esp or line_of_sight or first) and delay == 0
			and (not self._target_pos or vector.distance(target_pos, self._target_pos) >= 1
				or math.random(100) <= 5) then
		self._target_pos = target_pos
		delay = 0.2 + math.random() * 0.35
		local distance = vector.distance(self_pos, target_pos)
		if distance > 32 then delay = delay + 0.5 elseif distance > 16 then delay = delay + 0.25 end
		if not self:gopath(target_pos, self.pursuit_bonus) then delay = delay + 0.75 end
	end
	self._gopath_delay = delay
	delay = math.max(self._attack_delay - dtime, 0)
	if self:pre_melee_attack(vector.distance(self_pos, target_pos), delay, line_of_sight) then
		self:look_at(target_pos)
		self:custom_attack()
		delay = self.melee_interval
	end
	self._attack_delay = delay
end

------------------------------------------------------------------------
-- AI loop
------------------------------------------------------------------------

local IDLE = {pacing = true}

-- Runs the first ai_function that is active (a string names a new activity; true keeps
-- the current one), or the current one while it can't be interrupted.
function K:run_ai(dtime, moveresult)
	if self.dead then
		self:halt_in_tracks()
		return
	end
	local pos = self.object:get_pos()
	local active
	if self._can_interrupt_activity or not self._active_activity then
		for _, fn in ipairs(self.ai_functions or {}) do
			local a, uninterruptible = fn(self, pos, dtime, moveresult)
			if a then
				if a ~= true then
					local cur = self._active_activity
					if cur and cur ~= a then self[cur] = nil end
					self._active_activity, self._active_activity_function = a, fn
					self._can_interrupt_activity = not uninterruptible
				end
				active = a
				break
			end
		end
	else
		active = self._active_activity_function(self, pos, dtime, moveresult)
	end
	if not active then
		self:set_animation("stand")
		if self._active_activity then
			self[self._active_activity] = nil
			self._active_activity = nil
		end
	end
	if active and not IDLE[self._active_activity] then
		self.ai_idle_time = 0
	else
		self.ai_idle_time = self.ai_idle_time + dtime
		if not active then
			self:cancel_navigation()
			self:halt_in_tracks()
		end
	end
end

-- Wander to a random spot within pace_width now and then.
function K:check_pace(pos, dtime)
	if self.pacing then
		self._pace_time = (self._pace_time or 0) + dtime
		if self:navigation_finished() or self._pace_time > PACE_TIMEOUT then
			self.pacing = false
			self:cancel_navigation()
			self:set_animation("stand")
		end
		return true
	end
	if self.ai_idle_time > self.pace_interval and math.random(self.pace_chance) == 1 then
		local a, r = math.random() * 2 * math.pi, math.random() * self.pace_width
		if self:gopath(vector.new(pos.x + math.cos(a) * r, pos.y, pos.z + math.sin(a) * r), self.pace_bonus) then
			self.pacing, self._pace_time = true, 0
			return "pacing"
		end
	end
	return false
end

-- Bookkeeping of who hurt it (the last 5 s count as recent).
function K:ai_step(dtime)
	if self._recent_attacker then
		self._recent_attacker_age = (self._recent_attacker_age or 0) + dtime
		if not self._recent_attacker:is_valid() or self._recent_attacker_age > 5 then
			self._recent_attacker, self._recent_attacker_age = nil, 0
		end
	end
	if self._last_attacker and not self._last_attacker:is_valid() then self._last_attacker = nil end
end

function K:on_step(dtime, moveresult)
	local pos = self.object:get_pos()
	if not pos then return end
	self._targets_visible = {}
	moveresult = moveresult or NO_MOVE
	self._immersion_depth, self._liquidtype = self:check_standin(dtime, pos)
	if self.dead then
		self:motion_step(dtime, moveresult, pos)
		return
	end
	self:navigation_step(dtime, moveresult)
	self:motion_step(math.min(dtime, 0.1), moveresult, pos)
	self:update_timers(dtime)
	self:ai_step(dtime)
	if not self.fire_resistant then mcl_burning.tick(self.object, dtime, self) end
	if self.dead or not self.object:get_pos() then return end
	self:rotate_step(dtime)
	self:set_animation_speed()
	if math.random() < dtime / 3.5 then self:mob_sound("random") end
	self:run_targeting_rules(dtime, pos)
	self:run_ai(dtime, moveresult)
end

------------------------------------------------------------------------
-- Damage and death
------------------------------------------------------------------------

local attack_id = 0

-- Every hit ends here (punches, mcl_util.deal_damage): HP, who did it, death.
function K:receive_damage(reason, damage)
	if self.dead then return false end
	self.health = self.health - damage
	local source = reason.source
	if source and damage >= 0 then
		if source:is_player() then self.xp_timestamp = core.get_us_time() end -- (VoxeLibre: XP drop)
		self._recent_attacker, self._recent_attacker_age = source, 0
		attack_id = attack_id + 1
		self._last_attacker, self._last_attack_id = source, attack_id
	end
	self:check_for_death(reason, damage)
	return true
end

function K:deal_damage(damage, reason)
	self:receive_damage(reason or {type = "generic"}, damage)
	return true
end

function K:damage_mob(reason, damage)
	return self:receive_damage({type = reason}, damage)
end

function K:heal_mob(amount, hp_max)
	self.health = math.min(self.health + amount, hp_max or self.object:get_properties().hp_max)
	self.old_health = self.health
end

-- (Mineclonia's signature) VoxeLibre's own check does the red flash, sounds, drops, XP,
-- on_die, the die clip and the removal of the body.
function K:check_for_death(reason, damage)
	if damage <= 0 then return false end
	if self.dead then return true end
	local source = reason and reason.source
	local died = VL.check_for_death(self, reason and reason.type or "generic",
		{type = reason and reason.type, puncher = source}, {attacker_name = source and source:is_player() and "player" or nil})
	if self.state == "die" then
		self.dead = true
		self.object:set_acceleration(vector.zero()) -- (gravity is motion_step's)
	end
	return died
end

function K:on_punch(hitter, tflp, caps, dir)
	if self.dead or not caps or not hitter then return end
	if self.do_punch and self.do_punch(self, hitter, tflp, caps, dir) == false then return end
	local armor = self.object:get_armor_groups()
	local damage = 0
	for group, value in pairs(caps.damage_groups or {}) do
		local f = math.max(0, math.min(1, (tflp or 1) / (caps.full_punch_interval or 1.4)))
		damage = damage + value * f * (armor[group] or 0) / 100
	end
	if damage > 0 then core.sound_play("default_punch", {object = self.object, max_hear_distance = 5}, true) end
	-- a projectile's shooter is the source
	local ent = hitter:get_luaentity()
	local source = ent and (ent._shooter or ent._source_object
		or (type(ent._owner) == "string" and core.get_player_by_name(ent._owner))) or hitter
	mcl_util.deal_damage(self.object, damage, {type = hitter:is_player() and "player" or "mob", source = source, direct = hitter})
end

-- VoxeLibre's get_staticdata also forgets the target and the state: keep them.
function K:get_staticdata()
	local attack, state = self.attack, self.state
	self._targets_visible, self._object_search_lists = nil, nil -- (ObjectRefs inside tables)
	local data = VL.get_staticdata(self)
	self.attack, self.state, self._targets_visible, self._object_search_lists = attack, state, {}, {}
	return data
end

------------------------------------------------------------------------
-- Registration
------------------------------------------------------------------------

local SOUNDS = {mobs_mc_ghast_hurt = "mobs_mc_enderman_hurt"} -- (VoxeLibre's ghast has no hurt sound)
-- object properties: not copied onto the entity (the engine would read them from there)
local PROPS = {hp_min = true, hp_max = true, physical = true, collisionbox = true, selectionbox = true, visual = true,
	mesh = true, textures = true, visual_size = true, glow = true, makes_footstep_sound = true, stepheight = true}

-- VoxeLibre's register_mob copies only the fields it knows: register, then put the
-- kaiju's own fields and methods on the entity and this class under it.
function api.register_mob(name, def)
	local cb = def.collisionbox
	def.spawn_class = def.type == "monster" and "hostile" or "passive"
	def.can_despawn = false
	def.head_eye_height = def.head_eye_height or (cb[5] - cb[2]) * 0.75 + cb[2]
	def._kaiju_eye = def.head_eye_height
	-- (mob_activate takes the boxes and the size from here)
	def.initial_properties = {hp_min = def.hp_min, hp_max = def.hp_max, collisionbox = cb,
		selectionbox = def.selectionbox or cb, visual_size = def.visual_size}
	def.hp_min, def.hp_max = nil, nil -- (VoxeLibre warns about them at the top level)
	for k, s in pairs(def.sounds or {}) do
		if type(s) == "table" and SOUNDS[s.name] then
			def.sounds[k] = table.copy(s)
			def.sounds[k].name = SOUNDS[s.name]
		end
	end
	mcl_mobs.register_mob(name, def)
	local ent = core.registered_entities[name]
	ent.initial_properties.physical = def.physical ~= false -- (VoxeLibre: always true)
	-- (rawget: VoxeLibre's class has methods of the same names, e.g. gopath, check_for_death)
	for k, v in pairs(def) do
		if rawget(ent, k) == nil and not PROPS[k] then ent[k] = v end
	end
	ent.deal_damage = K.deal_damage
	ent.pushable = def.pushable ~= false -- (VoxeLibre: always true)
	setmetatable(ent, {__index = K})
	local activate = ent.on_activate
	ent.on_activate = function(self, staticdata, dtime)
		activate(self, staticdata, dtime)
		if not self.object:is_valid() then return end
		-- saved during its die clip: VoxeLibre's removal (core.after) did not survive the restart
		if self.dead then
			self.object:remove()
			return
		end
		self.collisionbox = cb
		self._targets_visible, self._object_search_lists = {}, {}
		self.object:set_acceleration(vector.zero())
		self:post_load_staticdata()
	end
end

-- Is obj the arrow's shooter, or one of its hit boxes?
local function own(self, obj)
	if obj == self._shooter then return true end
	local ent = obj:get_luaentity()
	return ent and ent.name == "kaiju_core:hitbox" and ent._owner == self._shooter
end

-- Mineclonia counts an arrow's _lifetime in server steps, VoxeLibre in seconds. VoxeLibre
-- looks for victims within 1.5 nodes of the arrow, which a fast one skips over: a raycast
-- along its path first. A hit on a kaiju's hit box (not a mob for VoxeLibre's arrows)
-- goes to the kaiju. The shooter and its hit boxes are never hit.
function api.register_arrow(name, def)
	if def._lifetime then def._lifetime = def._lifetime * 0.05 end
	def.allow_punching = function(self, _, _, obj) return not own(self, obj) end
	local hit_mob = def.hit_mob
	if hit_mob then
		def.hit_object = function(self, obj)
			local ent = obj:get_luaentity()
			local owner = ent and ent.name == "kaiju_core:hitbox" and ent._owner
			if owner and owner:is_valid() then hit_mob(self, owner) end
		end
	end
	mcl_mobs.register_arrow(name, def)
	-- (the raycast skips players without enable_pvp: the stock radius check still finds them)
	local behaviors = core.registered_entities[name]._vl_projectile.behaviors
	for i, b in ipairs(behaviors) do
		if b == vl_projectile.collides_with_entities then
			behaviors[i] = function(self, ...)
				vl_projectile.raycast_collides_with_entities(self, ...)
				if self._removed then return true end
				return b(self, ...)
			end
		end
	end
end

-- (VoxeLibre's passes no source: the victim would not know who to retaliate against.)
function api.get_arrow_damage_func(damage, typ, shooter)
	typ = mcl_damage.types[typ] and typ or "arrow"
	return function(projectile, obj)
		return mcl_util.deal_damage(obj, damage, {type = typ, source = shooter or projectile._shooter, direct = projectile.object})
	end
end
