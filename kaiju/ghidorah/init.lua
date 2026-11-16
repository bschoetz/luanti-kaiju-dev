local S = core.get_translator("ghidorah")
local mcl_mobs = kaiju_core.mcl_mobs -- (Mineclonia's, or the VoxeLibre layer)
local mob_class = mcl_mobs.mob_class
local kc = kaiju_core

------------------------------------------------------------------------
-- Model-derived numbers (printed by tools/ghidorah_model.py; model units, 1 unit = UNIT nodes)
------------------------------------------------------------------------

local SCALE = 7.5
local UNIT = SCALE / 10
local WALK_CYCLE_NODES = 10.057 * UNIT
-- Head joints (the pivots of the head_X bones, printed as "joint") per pose:
-- {forward, side (+ = the "_l" side, model +X = his right), up}.
-- stand: frame 0, also used for walk and bite; reared: the "beam" hold, which the hover
-- clips (hover, beam_fly, takeoff, land) match within 1.3 units; fly: body leaning 52 deg.
local HEAD_JOINT = {
	stand = {c = {5.13, -0.13, 22.60}, l = {3.59, 6.09, 21.89}, r = {4.31, -6.05, 21.44}},
	reared = {c = {8.24, -0.06, 20.24}, l = {6.97, 5.96, 19.56}, r = {6.90, -6.04, 19.54}},
	fly = {c = {14.71, -0.11, 12.53}, l = {13.40, 5.74, 12.81}, r = {13.34, -5.93, 12.76}},
}
local POSE = {beam = "reared", beam_fly = "reared", hover = "reared", takeoff = "reared", land = "reared", fly = "fly"}
local MOUTH_LEN = {c = 5.8, l = 5.0, r = 5.0} -- joint to mouth opening (MOUTH_OFS * HEAD_SCALE)
local HEAD_CENTRE = 3.0                        -- joint to the middle of the skull
local BEAM_POSE_PITCH = math.rad(-14.5)        -- the "beam" hold points the heads this far down
-- Tail segment midpoints of the two splayed tails (tools/ghidorah_model.py TAIL/TAIL_W):
-- {distance behind, centre height, thickness, spikes (fan at the tip), sideways offset}
local TAIL = {
	{4.4, 8.05, 3.0, 1.3, 1.7}, {8.4, 6.95, 2.5, 1.15, 2.5}, {12.4, 5.3, 2.0, 1.0, 3.3},
	{16.3, 3.75, 1.5, 0.85, 4.1}, {20.0, 3.2, 1.1, 2.4, 4.8},
}

------------------------------------------------------------------------
-- Tunables
------------------------------------------------------------------------

local SWIM_DEPTH = 12          -- nodes of water above his feet before he swims
local HEAD_HP = 120
local REGROW_TIME = 30         -- seconds until a severed head has grown back
local HEAD_HIT_RADIUS = 2.0    -- nodes; a hit this close to a head goes to that head
local BEAM_INTERVAL = 8        -- seconds between beam volleys
local BEAM_TIME = 2.5          -- matches the "beam" animation (50 frames at 20 fps)
local BEAM_START = 0.5         -- rear-up part of the animation before the beams fire
local BEAM_TICK = 0.25
local BEAM_DAMAGE = 3          -- per head and tick
local BEAM_PLAYER_DAMAGE = 1   -- ... against players (the heads' hits of a tick are dealt as one: beams_step)
local BEAM_RANGE = 40
local BEAM_MIN_DIST = 8
local BEAM_MIN_TIME = 1.5      -- on the ground: the target must have been that far away for this long
local SIDE_MAIN_INTERVAL = 12  -- seconds between the side heads' volleys at a main target in melee
local SIDE_MAIN_DAMAGE = 1     -- per head and tick in those (he doesn't bite meanwhile)
local BLAST_INTERVAL = 1.0     -- per head: a small explosion where a beam hits the ground
local FLY_SPEED = 9
local WANDER_SPEED = 5
local ALTITUDE = 18            -- roaming height above ground
local MIN_CLEARANCE = 12
local CIRCLE_RADIUS = 20
local CIRCLE_HEIGHT = 10       -- above a ground target's head
local MAX_ALTITUDE = 40        -- never circle higher than this above the ground (no climbing race with Mothra)
local TAKEOFF_TIME = 1.0       -- "takeoff" animation (20 frames at 20 fps)
local LAND_TIME = 1.0
local AIRBORNE_TARGET = 6      -- a target this high above its ground counts as flying
local FAR_TARGET = 48          -- fly to targets further than this
local LAND_DIST = 25           -- land when a ground target is closer than this
local IDLE_FLIGHT = 15         -- land after flying this long without a target
local FLY_ROOM = 6             -- free nodes above his head that he needs to take off
local NO_FLY_TIME = 20         -- seconds on foot after a wall or a low roof ended a flight
local LAND_RING = 12           -- landing spots are tried this far around the target
local LAND_TRANSIT = 10        -- seconds to reach a landing spot, then he comes down where he is
local HEAD_AIM_MAX = math.rad(60)

-- Smashing in the air: his heads are 11 nodes ahead of his feet in the fly pose; no floor
-- layer and no tail, and natural terrain stays (kaiju_core.smash).
local FLY_SMASH = {lookahead = 12, keep = "natural"}

local HEADS = {"c", "l", "r"}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- World position of a model-space point {forward, side, up} for the current yaw.
local function model_point(self, p)
	return kc.model_point(self, p[1] * UNIT, p[2] * UNIT, p[3] * UNIT)
end

local function centre_of(obj)
	local cb = obj:get_properties().collisionbox
	return vector.offset(obj:get_pos(), 0, (cb[2] + cb[5]) / 2, 0)
end

local function top_of(obj)
	return obj:get_pos().y + obj:get_properties().collisionbox[5]
end

-- The kaiju he hunts on sight.
local function is_archenemy(ent)
	return ent and (ent.name == "gojira:gojira" or ent.name == "mothra:mothra")
end

local function head_alive(self, h)
	return not (self._head_regrow and self._head_regrow[h])
end

-- World position of a head's joint in the pose of the current animation, `ahead` model
-- units further along the body's forward direction.
local function head_joint(self, h, ahead)
	local j = HEAD_JOINT[POSE[self._current_animation] or "stand"][h]
	return model_point(self, {j[1] + (ahead or 0), j[2], j[3]})
end

-- Yaw (relative to the body, counter-clockwise) and pitch from `from` to the point `to`.
local function aim_angles(self, from, to)
	local d = vector.subtract(to, from)
	local yaw_off = (math.atan2(d.z, d.x) - math.pi / 2 - self.object:get_yaw() + math.pi) % (2 * math.pi) - math.pi
	return yaw_off, math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z))
end

local function clamp_aim(a)
	return math.max(-HEAD_AIM_MAX, math.min(HEAD_AIM_MAX, a))
end

local function head_burst(self, h, amount)
	local p = head_joint(self, h, HEAD_CENTRE)
	core.add_particlespawner({
		amount = amount, time = 0.4,
		pos = {min = vector.offset(p, -1, -1, -1), max = vector.offset(p, 1, 1, 1)},
		vel = {min = vector.new(-5, 0, -5), max = vector.new(5, 6, 5)},
		acc = vector.new(0, -9.81, 0),
		exptime = {min = 0.8, max = 1.6}, size = {min = 2, max = 5}, glow = 10,
		texture = "mcl_particles_effect.png^[colorize:#f2d16b:220",
	})
end

------------------------------------------------------------------------
-- Heads: own HP, severing and regrowth
------------------------------------------------------------------------

-- Note: set_bone_override replaces the whole override of a bone, so this drops the aim
-- rotation of a severed head; aim_head adds it back once the head is alive again.
local function apply_head_scale(self, h, interpolation)
	local severed = not head_alive(self, h)
	-- scale 0 would collapse the bone matrix; 0.01 is invisible at kaiju size
	local s = severed and 0.01 or 1
	self.object:set_bone_override("head_" .. h, {
		scale = {vec = vector.new(s, s, s), interpolation = interpolation, absolute = false},
	})
end

local function sever_head(self, h, reason)
	self._head_regrow = self._head_regrow or {}
	self._head_regrow[h] = self._regrow_time
	self["_head_target_" .. h] = nil
	apply_head_scale(self, h, 0.3)
	head_burst(self, h, 60)
	-- all three heads off at the same time: the king falls
	for _, other in ipairs(HEADS) do
		if head_alive(self, other) then return end
	end
	self.health = 0
	self:check_for_death(reason, 1) -- (damage <= 0 would skip the death handling)
end

local function regrow_step(self, dtime)
	if not self._head_regrow then return end
	for h, t in pairs(self._head_regrow) do
		t = t - dtime
		if t <= 0 then
			self._head_regrow[h] = nil
			self._head_hp[h] = HEAD_HP
			self["_aim_" .. h] = nil -- the override below drops the rotation: aim_head must send it again
			apply_head_scale(self, h, 3.0) -- grows back over 3 s
			self:mob_sound("random")
		else
			self._head_regrow[h] = t
		end
	end
end

-- Which head (if any) another mob's hit lands on: the one closest to that mob's body,
-- feet to top (the server doesn't know where its jaws are). Players and projectiles hit
-- the hit boxes below instead.
local function hit_head(self, reason)
	local direct = reason.direct
	local ent = direct and direct:is_valid() and direct:get_luaentity()
	if not (ent and ent.is_mob) then return nil end
	local from, dir, len = direct:get_pos(), vector.new(0, 1, 0), direct:get_properties().collisionbox[5]
	local best, best_d
	for _, h in ipairs(HEADS) do
		if head_alive(self, h) then
			local hp = head_joint(self, h, HEAD_CENTRE)
			local t = math.max(0, math.min(len, vector.dot(vector.subtract(hp, from), dir)))
			local d = vector.distance(hp, vector.add(from, vector.multiply(dir, t)))
			if d <= HEAD_HIT_RADIUS and (not best_d or d < best_d) then
				best, best_d = h, d
			end
		end
	end
	return best
end

------------------------------------------------------------------------
-- Hit boxes
------------------------------------------------------------------------

-- The heads and the chest carry hit boxes of their own (kaiju_core.ensure_hitboxes: his
-- position is at his feet, and one selection box can't follow three heads; a rotating one
-- is not hit reliably by server raycasts). `_hit_part` tells receive_damage where.
local HITBOXES = {{
	name = "chest", box = {-3, -4.5, -3, 3, 4.5, 3},
	pos = function(self)
		-- halfway between the hips and the centre neck: follows the lean in flight
		local j = HEAD_JOINT[POSE[self._current_animation] or "stand"].c
		return model_point(self, {j[1] / 2, 0, (j[3] + 10) / 2})
	end,
}}
for _, h in ipairs(HEADS) do
	-- (a stump's box is at the joint: the skull it was around is gone)
	HITBOXES[#HITBOXES + 1] = {name = h, pos = function(self) return head_joint(self, h, head_alive(self, h) and HEAD_CENTRE or 0) end}
end

------------------------------------------------------------------------
-- Gravity beams
------------------------------------------------------------------------

local function is_enemy(self, obj)
	if not obj or obj == self.object or not obj:is_valid() then return false end
	-- creative/peaceful/dead players are no enemies: beams pass through them
	if obj:is_player() then return self:attack_player_allowed(obj) end
	local ent = obj:get_luaentity()
	return ent and ent.is_mob and not ent.dead and ent.name ~= "ghidorah:ghidorah"
end

-- Where head h's beam at target starts (the mouth) and its direction. The beam leaves the
-- mouth along the direction the head is turned to (aim_head), so a target outside the
-- heads' HEAD_AIM_MAX cone is missed instead of shot through his own body.
local function beam_ray(self, h, target)
	local joint = head_joint(self, h)
	local yaw_off, pitch = aim_angles(self, joint, centre_of(target))
	local yaw = self.object:get_yaw() + clamp_aim(yaw_off)
	pitch = clamp_aim(pitch)
	local dir = vector.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
	return vector.add(joint, vector.multiply(dir, MOUTH_LEN[h] * UNIT)), dir
end

-- Players and kaiju stop a beam; smaller mobs are hurt and let it through.
local function stops_beam(obj)
	return obj:is_player() or kc.is_kaiju(obj:get_luaentity())
end

-- Would head h's beam hit target: is it the first thing on the line that stops a beam?
-- (A dry run of beam_tick. In melee the side heads can't turn far enough down for a target's
-- centre, but the clamped beam still enters a kaiju's box; a player's it misses.)
local function beam_reaches(self, h, target)
	local from, dir = beam_ray(self, h, target)
	for pointed in core.raycast(from, vector.add(from, vector.multiply(dir, BEAM_RANGE)), true, false) do
		if pointed.type == "node" then return false end
		local obj = pointed.ref
		if obj == target then return true end
		if obj ~= self.object and is_enemy(self, obj) and stops_beam(obj) then return false end
	end
	return false
end

-- One tick of head h's beam at target. Enemies on the line take `damage`; a player is
-- only counted in player_hits (player -> heads that hit it in this tick, see beams_step).
local function beam_tick(self, h, target, do_blast, damage, player_hits)
	local from, dir = beam_ray(self, h, target)
	local to = vector.add(from, vector.multiply(dir, BEAM_RANGE))
	local hit_pos
	for pointed in core.raycast(from, to, true, false) do
		if pointed.type == "object" then
			local obj = pointed.ref
			if obj ~= self.object and is_enemy(self, obj) then
				local at, stops = pointed.intersection_point or obj:get_pos(), obj == target or stops_beam(obj)
				if obj:is_player() then
					player_hits[obj] = (player_hits[obj] or 0) + 1
				else
					mcl_util.deal_damage(obj, damage, {type = "mob", source = self.object, direct = self.object})
				end
				if stops then
					hit_pos = at
					break
				end
			end
		elseif pointed.type == "node" then
			hit_pos = pointed.intersection_point or pointed.above
			if do_blast and kc.griefing_enabled("ghidorah:ghidorah", "kaiju_ghidorah_beam_blasts") then
				mcl_explosions.explode(pointed.above, 1, {drop_chance = 0.1, fire = false}, self.object)
			end
			break
		end
	end
	hit_pos = hit_pos or to
	-- Sparks shot from the mouth so fast that they reach the hit point as they expire: all
	-- those under way at any moment form a continuous, slightly ragged line.
	local dist = vector.distance(from, hit_pos)
	local v = vector.multiply(dir, dist / BEAM_TICK)
	core.add_particlespawner({
		amount = 20 + math.ceil(dist * 4), time = BEAM_TICK,
		pos = {min = vector.offset(from, -0.2, -0.2, -0.2), max = vector.offset(from, 0.2, 0.2, 0.2)},
		vel = {min = vector.offset(v, -1.5, -1.5, -1.5), max = vector.offset(v, 1.5, 1.5, 1.5)},
		exptime = BEAM_TICK, size = {min = 4, max = 8}, glow = 14,
		texture = "mcl_particles_crit.png^[colorize:#ffe14a:200",
	})
end

-- Can the head whose joint is at `from` turn far enough to beam at obj?
local function can_aim(self, from, obj)
	local to = centre_of(obj)
	if vector.distance(from, to) > BEAM_RANGE then return false end
	local yaw_off, pitch = aim_angles(self, from, to)
	return math.abs(yaw_off) <= HEAD_AIM_MAX and math.abs(pitch) <= HEAD_AIM_MAX
end

-- Side heads pick their own enemy (not the main target); default: the main target.
local function head_target(self, h)
	-- one top-level field per head: mcl_mobs drops ObjectRefs from staticdata only at the
	-- top level, an ObjectRef inside a table would break saving
	local key = "_head_target_" .. h
	if not head_alive(self, h) then
		-- a stump has no target (sever_head cleared it; a kept one would start side
		-- volleys that fire nothing)
		return nil
	end
	if h == "c" or not self.attack then return self.attack end
	local pos = head_joint(self, h)
	local t = self[key]
	if t and t:is_valid() and is_enemy(self, t) and can_aim(self, pos, t) then return t end
	self[key] = nil
	-- look for a new one at most once a second (a 40-node object search per head)
	local now = core.get_gametime()
	if self["_head_search_" .. h] == now then return self.attack end
	self["_head_search_" .. h] = now
	local other = self["_head_target_" .. (h == "l" and "r" or "l")]
	local best, best_d
	for obj in core.objects_inside_radius(pos, BEAM_RANGE) do
		if is_enemy(self, obj) and obj ~= self.attack and self:test_object_and_restriction(obj, obj:get_pos())
				and (obj:is_player() or kc.is_kaiju(obj:get_luaentity())) -- (is_enemy: no other Ghidorah)
				and can_aim(self, pos, obj) and core.line_of_sight(pos, centre_of(obj)) then
			-- rather one the other side head doesn't have; otherwise both beam the same
			local d = vector.distance(pos, obj:get_pos()) + (obj == other and BEAM_RANGE or 0)
			if not best_d or d < best_d then best, best_d = obj, d end
		end
	end
	self[key] = best
	return best or self.attack
end

-- Turn a head towards its target on top of the animation (throttled: each call is a
-- network message to every client).
local function aim_head(self, h, target)
	if not head_alive(self, h) then return end -- severed: apply_head_scale owns the override
	local key = "_aim_" .. h
	local yaw_off, pitch = 0, 0
	if target and target:is_valid() and target:get_pos() then
		yaw_off, pitch = aim_angles(self, head_joint(self, h), centre_of(target))
		yaw_off, pitch = clamp_aim(yaw_off), clamp_aim(pitch)
		-- the override turns the head on top of the animation: undo the clip's own pitch
		if self._current_animation == "beam" then pitch = pitch - BEAM_POSE_PITCH end
	end
	local last = self[key]
	if last and math.abs(last[1] - yaw_off) < 0.03 and math.abs(last[2] - pitch) < 0.03 then return end
	self[key] = {yaw_off, pitch}
	-- measured in the client (tests/ghidorah_show): +x = nose down, +z = nose towards
	-- model +X, i.e. clockwise; yaw_off is counter-clockwise like entity yaw
	self.object:set_bone_override("head_" .. h, {
		rotation = {vec = vector.new(-pitch, 0, -yaw_off), interpolation = 0.2, absolute = false},
		-- same interpolation as the regrowth, so aiming doesn't cut a growing head short
		scale = {vec = vector.new(1, 1, 1), interpolation = 3.0, absolute = false},
	})
end

-- A side head beaming on its own (see start_beams) opens its jaw by a bone override; the
-- full volleys have the "beam" clips for that. +x = jaw down, like the heads.
local function set_side_jaws(self, open)
	for _, h in ipairs({"l", "r"}) do
		self.object:set_bone_override("jaw_" .. h, open and {
			rotation = {vec = vector.new(0.7, 0, 0), interpolation = 0.2, absolute = false},
		} or nil)
	end
end

local function end_beams(self)
	if not self._beam_time then return end
	self._beam_time = nil
	if self._beam_side then
		set_side_jaws(self, false)
		self._beam_side = nil
	else
		self._anim_lock = 0
	end
end

local function beams_step(self, dtime)
	if not self._beam_time then return end
	self._beam_time = self._beam_time - dtime
	local elapsed = BEAM_TIME - self._beam_time
	self._beam_tick = (self._beam_tick or 0) - dtime
	if elapsed >= BEAM_START and self._beam_tick <= 0 then
		self._beam_tick = BEAM_TICK
		self._blast_timer = (self._blast_timer or 0) - BEAM_TICK
		local blast = self._blast_timer <= 0
		if blast then self._blast_timer = BLAST_INTERVAL end
		local player_hits = {}
		-- a side volley: only the side heads, at their own enemies, or ("main") at the main
		-- target, and then only while the beam would hit it
		local main = self._beam_side == "main"
		for _, h in ipairs(HEADS) do
			local t = head_target(self, h)
			if head_alive(self, h) and t and t:is_valid()
					and not (self._beam_side and (h == "c" or (t == self.attack) ~= main))
					and (not main or beam_reaches(self, h, t)) then
				beam_tick(self, h, t, blast, main and SIDE_MAIN_DAMAGE or BEAM_DAMAGE, player_hits)
				self._beam_fired = true
			end
		end
		-- One hit per player and tick for all heads: armour takes a share of every hit, and
		-- VoxeLibre rounds what is left to whole HP (1 through iron armour: 0).
		for player, n in pairs(player_hits) do
			mcl_util.deal_damage(player, n * BEAM_PLAYER_DAMAGE, {type = "mob", source = self.object, direct = self.object})
		end
	end
	if self._beam_time <= 0 then
		local main = self._beam_side == "main" -- (has its own cooldown: ground_attack)
		end_beams(self)
		-- (a side head whose enemy got away before it could fire tries again soon)
		if not main then self._beam_cooldown = self._beam_fired and BEAM_INTERVAL or 2 end
	end
end

-- side_only: the main target is too close for beams (he bites it), but a side head has an
-- enemy of its own: only those heads fire, while the body keeps walking and biting.
-- side_only = "main": the side heads fire at the main target in melee instead, and he
-- doesn't bite meanwhile (pre_melee_attack).
local function start_beams(self, side_only)
	self._beam_time = BEAM_TIME
	self._beam_tick = 0
	self._beam_fired = nil
	self._beam_side = side_only
	if side_only then
		set_side_jaws(self, true)
	else
		kc.play(self, self._flying and "beam_fly" or "beam", BEAM_TIME)
	end
	self:mob_sound("shoot_attack")
end

------------------------------------------------------------------------
-- Mob definition
------------------------------------------------------------------------

local ghidorah = {
	description = S("King Ghidorah"),
	type = "monster",
	_spawn_category = "misc",
	persistent = true,
	hp_min = 600,
	hp_max = 600,
	xp_min = 300,
	xp_max = 300,
	armor = 50,
	collisionbox = {-2.6, 0, -2.6, 2.6, 15, 2.6},
	selectionbox = {-3, 0, -3, 3, 15, 3},
	head_eye_height = 16,
	doll_size_override = {x = 0.15, y = 0.15},
	visual = "mesh",
	mesh = "ghidorah.glb",
	textures = {{"ghidorah.png"}},
	visual_size = {x = SCALE, y = SCALE},
	makes_footstep_sound = true,
	stepheight = 1.1,
	movement_speed = 7.5,
	pace_bonus = 0.5,
	floats = 0,
	water_velocity = 3.0,
	damage = 10,               -- his bite is the weaker one (Gojira: 18); his weapon is the beams
	reach = 8,
	melee_interval = 1.5,
	attack_type = "null",
	view_range = 64,
	tracking_distance = 80,
	fire_resistant = true,
	_fire_resistant = true,
	_no_fall_damage = true,
	can_ride_boat = false,
	can_ride_cart = false,
	drops = {
		{name = "mcl_core:goldblock", chance = 1, min = 4, max = 8, looting = "common"},
		{name = "mcl_core:diamond", chance = 1, min = 4, max = 8, looting = "common"},
	},
	sounds = {
		random = {name = "mobs_mc_parrot_random", gain = 2.5}, -- pitched down: a cackling trill
		attack = {name = "mobs_mc_ender_dragon_attack", gain = 2.5},
		shoot_attack = {name = "mobs_mc_ender_dragon_shoot", gain = 2.5},
		war_cry = {name = "mobs_mc_wither_spawn", gain = 2},
		damage = {name = "mobs_mc_ghast_hurt", gain = 2},
		death = {name = "mobs_mc_wither_spawn", gain = 2.5},
		base_pitch = 0.5,
		distance = 96,
	},
	-- frame ranges match tools/ghidorah_model.py (glTF time in seconds, exported at 1 fps)
	animation = {
		stand_start = 0, stand_end = 60, stand_speed = 15,
		walk_start = 70, walk_end = 110, walk_speed = 40 / WALK_CYCLE_NODES,
		fly_start = 120, fly_end = 150, fly_speed = 24,
		hover_start = 160, hover_end = 200, hover_speed = 20,
		punch_start = 210, punch_end = 230, punch_speed = 25, -- bite
		beam_start = 240, beam_end = 290, beam_speed = 20, beam_loop = false,
		beam_fly_start = 410, beam_fly_end = 450, beam_fly_speed = 20,
		takeoff_start = 300, takeoff_end = 320, takeoff_speed = 20, takeoff_loop = false,
		land_start = 330, land_end = 350, land_speed = 20, land_loop = false,
		die_start = 360, die_end = 400, die_speed = 10, die_loop = false,
	},
	_smash = {lookahead = 3, tail = {segments = TAIL, unit = UNIT, first = 2}},
	_regrow_time = REGROW_TIME, -- per entity, so tests can shorten it
}

-- One-shot clips (beam, takeoff, land) lock the animation: mcl_mobs sets walk/stand/punch
-- on its own whenever he is on the ground.
kc.lock_animations(ghidorah)

------------------------------------------------------------------------
-- Walking and flying
------------------------------------------------------------------------

-- Clear of the ground on the way to his goal. What he may smash is not ground: he flies
-- through trees and towers and tears them down (ai_step). With smashing off he flies over.
local function keep_clearance(self, self_pos, dtime)
	kc.keep_clearance(self, self_pos, dtime, MIN_CLEARANCE, kc.griefing_enabled("ghidorah:ghidorah", "kaiju_smash_blocks"))
end

local function take_off(self)
	self.attacking = nil
	self._flying = true
	self._land = nil
	self._idle_flight = 0
	kc.end_bulldoze(self) -- or `stuck` in choose_mode is still true after landing: he'd take off again
	self:cancel_navigation()
	self:halt_in_tracks(true)
	self.object:set_properties({physical = false})
	self._land_spot, self._land_try, self._land_time = nil, nil, nil
	self._blocked, self._floor = nil, nil -- (of the last flight)
	local pos, height = self.object:get_pos(), self.collisionbox[5]
	local goal = vector.offset(pos, 0, ALTITUDE, 0)
	local roof = kc.ceiling_y(vector.offset(pos, 0, 1, 0), ALTITUDE + height + 1)
	if roof then goal.y = math.min(goal.y, roof - height - 2) end
	self._goal = goal
	self._goal_speed = FLY_SPEED
	kc.play(self, "takeoff", TAKEOFF_TIME)
	self:mob_sound("war_cry")
end

local function touch_down(self)
	self.attacking = nil
	-- clear the landing spot so he doesn't land inside trees or houses
	if kc.griefing_enabled("ghidorah:ghidorah", "kaiju_smash_blocks") then
		kc.smash(self, {lookahead = 0})
	end
	self._flying = nil
	self._land = nil
	self._land_spot, self._land_try, self._land_time = nil, nil, nil
	self._goal = nil
	self.object:set_velocity(vector.zero())
	self.object:set_properties({physical = true})
	kc.play(self, "land", LAND_TIME)
end

-- Where to land (choose_mode, up to 3 candidates a second): below him, or else the nearest
-- of 8 spots around the target (LAND_RING away; without a target near him, 10 and 20
-- nodes around himself) that is level, dry ground and not a tree top (kc.landing_ok). If
-- none of the 9 is, he comes down where he is, as he always did (touch_down clears the
-- spot if he may smash). The spot is a plain table: it is saved with him.
local function find_landing_spot(self, self_pos)
	local t = self.attack and self.attack:is_valid() and self.attack:get_pos()
	if t and kc.flat_dist(t, self_pos) > LAND_DIST + 5 then t = nil end
	local c, spots = t or self_pos, {}
	for k = 0, 7 do
		local a, d = k * math.pi / 4, t and LAND_RING or (k % 2 == 0 and 10 or 20)
		spots[k + 1] = vector.new(c.x + math.cos(a) * d, self_pos.y, c.z + math.sin(a) * d)
	end
	table.sort(spots, function(a, b) return kc.flat_dist(a, self_pos) < kc.flat_dist(b, self_pos) end)
	table.insert(spots, 1, self_pos)
	local tried = self._land_try or 0
	for i = tried + 1, math.min(tried + 3, #spots) do
		local y = kc.landing_ok(spots[i], self.collisionbox)
		if y then
			self._land_spot = {x = spots[i].x, y = y, z = spots[i].z}
			return
		end
	end
	self._land_try = tried + 3
	if self._land_try >= #spots then
		self._land_spot = {x = self_pos.x, y = self_pos.y, z = self_pos.z}
	end
end

-- Decide (once a second) whether to switch between walking and flying.
local function choose_mode(self, self_pos, dtime)
	self._no_fly = math.max((self._no_fly or 0) - dtime, 0)
	self._mode_timer = (self._mode_timer or 0) - dtime
	if self._mode_timer > 0 or (self._anim_lock or 0) > 0 or self._beam_time then return end
	self._mode_timer = 1
	local t = self.attack
	if not self._flying then
		if t and t:is_valid() then
			local tp = t:get_pos()
			local airborne = tp.y - kc.ground_y(tp) > AIRBORNE_TARGET
			self._target_airborne = airborne
			local far = vector.distance(self_pos, tp) > FAR_TARGET
			local stuck = (self._bulldoze_time or 0) > 0 and (self._stuck_flights or 0) < 3
			-- not under a roof (leaves are none), and not right after one ended a flight
			if (airborne or far or stuck) and self._no_fly == 0
					and not kc.ceiling_y(vector.offset(self_pos, 0, 1, 0), self.collisionbox[5] + FLY_ROOM - 1) then
				if stuck then self._stuck_flights = (self._stuck_flights or 0) + 1 end
				take_off(self)
			end
		end
	elseif not self._land then
		if self._blocked then
			-- a wall or a roof too low to fly under is in the way (kc.keep_clearance): on
			-- foot from here, where he walks, bulldozes and beams
			self._land, self._no_fly = true, NO_FLY_TIME
		elseif t and t:is_valid() then
			self._idle_flight = 0
			local tp = t:get_pos()
			local airborne = tp.y - kc.ground_y(tp) > AIRBORNE_TARGET
			self._target_airborne = airborne
			local flat = vector.distance(vector.new(tp.x, 0, tp.z), vector.new(self_pos.x, 0, self_pos.z))
			if not airborne and flat < LAND_DIST then self._land = true end
		else
			self._idle_flight = (self._idle_flight or 0) + 1
			if self._idle_flight >= IDLE_FLIGHT then self._land = true end
		end
	end
	if self._flying and self._land and not self._land_spot then find_landing_spot(self, self_pos) end
end

function ghidorah:motion_step(dtime, moveresult, self_pos)
	if not self._flying then
		return mob_class.motion_step(self, dtime, moveresult, self_pos)
	end
	if self.dead then
		kc.death_fall(self, self_pos)
		return
	end
	if self._land then
		local spot = self._land_spot
		self._goal_speed = FLY_SPEED -- he can't attack while landing: come down fast
		if not spot then
			self._goal = vector.copy(self_pos) -- (choose_mode is still looking for a spot)
		elseif kc.flat_dist(self_pos, spot) > 1.5 and (self._land_time or 0) < LAND_TRANSIT then
			-- over to the spot at his height, clear of the terrain on the way
			self._land_time = (self._land_time or 0) + dtime
			self._goal = vector.new(spot.x, math.max(self_pos.y, spot.y + MIN_CLEARANCE), spot.z)
			keep_clearance(self, self_pos, dtime)
		else
			-- straight down (keep_clearance would hold him up)
			local ground = kc.ground_y(self_pos)
			self._goal = vector.new(self_pos.x, ground, self_pos.z)
			self._floor = nil
			if self_pos.y - ground < 1.5 then
				touch_down(self)
				return
			end
		end
	end
	local want = kc.fly_velocity(self, dtime, self_pos, WANDER_SPEED)
	if self.attack and self.attack:is_valid() then
		self:look_at(self.attack:get_pos())
	elseif vector.length(vector.new(want.x, 0, want.z)) > 0.5 then
		self:set_yaw(math.atan2(want.z, want.x) - math.pi / 2)
	end
end

local function fly_wander(self, self_pos, dtime)
	self._wander_timer = (self._wander_timer or 0) - dtime
	local goal = self._goal
	if not goal or self._wander_timer <= 0 or vector.distance(self_pos, goal) < 3 then
		local ang, dist = math.random() * 2 * math.pi, 20 + math.random() * 30
		local p = vector.offset(self_pos, math.cos(ang) * dist, 0, math.sin(ang) * dist)
		p.y = kc.cruise_y(p, self_pos.y, ALTITUDE + math.random() * 8, self.collisionbox[5])
		self._goal, self._goal_speed = p, WANDER_SPEED
		self._wander_timer = 8 + math.random() * 6
	end
	self:set_animation("fly")
end

-- Ground attack: beams on a cooldown, otherwise bite with mcl_mobs' melee (and bulldoze).
local function ground_attack(self, attach_pos, self_pos, dtime, target_pos, line_of_sight)
	if self._beam_time and not self._beam_side then
		self:look_at(target_pos)
		return
	end
	local dist = vector.distance(attach_pos, target_pos)
	-- A melee opponent that a gust or a landing only knocked a few nodes away (the two walk
	-- back at once) gets no volley: the beams are for targets that stay at a distance.
	self._beam_far = dist >= BEAM_MIN_DIST and (self._beam_far or 0) + dtime or 0
	if not self._beam_time and (self._beam_cooldown or 0) <= 0 then
		local in_range = line_of_sight and dist >= BEAM_MIN_DIST and dist <= BEAM_RANGE
		if in_range and self._beam_far >= BEAM_MIN_TIME then
			self._punch_animation_timeout = nil
			self:halt_in_tracks(true)
			self:cancel_navigation()
			start_beams(self)
			return
		elseif not in_range and (self._head_target_l or self._head_target_r) then
			start_beams(self, true)
		end
	end
	-- A main target in melee and no other enemy for the side heads: every SIDE_MAIN_INTERVAL
	-- they fire a volley at it, if a beam would hit (looked at once a second).
	if not self._beam_time and dist < BEAM_MIN_DIST and (self._side_main_cd or 0) <= 0
			and not (self._head_target_l or self._head_target_r) then
		self._side_main_cd = 1
		if (head_alive(self, "l") and beam_reaches(self, "l", self.attack))
				or (head_alive(self, "r") and beam_reaches(self, "r", self.attack)) then
			start_beams(self, "main")
			self._side_main_cd = SIDE_MAIN_INTERVAL
		end
	end
	kc.update_bulldoze(self, dtime, attach_pos, target_pos)
	return mob_class.attack_melee(self, attach_pos, self_pos, dtime, target_pos, line_of_sight)
end

-- Air attack: circle above the target and fire beams.
local function air_attack(self, self_pos, dtime, target_pos, line_of_sight)
	self._circle = (self._circle or math.random() * 2 * math.pi) + dtime * FLY_SPEED / CIRCLE_RADIUS
	local top
	if self._target_airborne then
		-- level with a flying enemy (his centre at its centre) instead of above it
		top = centre_of(self.attack).y - 7.5
	else
		top = top_of(self.attack) + CIRCLE_HEIGHT
	end
	top = math.min(top, kc.ground_y(target_pos) + MAX_ALTITUDE)
	local r = line_of_sight and CIRCLE_RADIUS or 0
	self._goal = vector.new(target_pos.x + math.cos(self._circle) * r, top, target_pos.z + math.sin(self._circle) * r)
	self._goal_speed = FLY_SPEED
	keep_clearance(self, self_pos, dtime)
	if not self._beam_time and (self._beam_cooldown or 0) <= 0 and line_of_sight
			and vector.distance(self_pos, target_pos) <= BEAM_RANGE then
		start_beams(self)
	elseif not self._beam_time then
		self:set_animation("fly")
	end
end

function ghidorah:attack_null(attach_pos, self_pos, dtime, target_pos, line_of_sight)
	if self._fight_target ~= self.attack then
		-- a new enemy gets the beams soon (and without the wait of ground_attack)
		self._fight_target = self.attack
		self._beam_cooldown = math.min(self._beam_cooldown or 0, 2)
		self._beam_far = BEAM_MIN_TIME
	end
	if self._flying then
		-- (on the ground mob_class.attack_melee owns self.attacking and initialises its
		-- state while it is false; take_off/touch_down reset it when the mode changes)
		self.attacking = true
		return air_attack(self, self_pos, dtime, target_pos, line_of_sight)
	end
	return ground_attack(self, attach_pos, self_pos, dtime, target_pos, line_of_sight)
end

function ghidorah:run_ai(dtime, moveresult)
	local self_pos = self.object:get_pos()
	if self._anim_lock then self._anim_lock = self._anim_lock - dtime end
	self._beam_cooldown = math.max((self._beam_cooldown or 0) - dtime, 0)
	self._side_main_cd = math.max((self._side_main_cd or 0) - dtime, 0)
	kc.ensure_hitboxes(self, HITBOXES)
	regrow_step(self, dtime)
	beams_step(self, dtime)
	choose_mode(self, self_pos, dtime)
	-- heads: aim at their targets ~5x a second
	self._aim_timer = (self._aim_timer or 0) - dtime
	if self._aim_timer <= 0 then
		self._aim_timer = 0.2
		for _, h in ipairs(HEADS) do aim_head(self, h, head_target(self, h)) end
	end
	if not self._flying then
		-- touched down: stand still until the "land" clip is through
		if self._current_animation == "land" and (self._anim_lock or 0) > 0 then return end
		return mob_class.run_ai(self, dtime, moveresult)
	end
	if self._land then
		self:set_animation("hover")
		return
	end
	if self:check_attack(self_pos, dtime) then
		return
	end
	self.attacking = nil
	fly_wander(self, self_pos, dtime)
	keep_clearance(self, self_pos, dtime)
end

function ghidorah:attack_end()
	end_beams(self)
	self._fight_target = nil
	for _, h in ipairs(HEADS) do self["_head_target_" .. h] = nil end
	self._stuck_flights = 0
	kc.end_bulldoze(self)
	return mob_class.attack_end(self)
end

-- No bite while the side heads fire at the main target.
function ghidorah:pre_melee_attack(distance, delay, line_of_sight)
	if self._beam_side == "main" then return false end
	return mob_class.pre_melee_attack(self, distance, delay, line_of_sight)
end

function ghidorah:gopath(...)
	return kc.gopath(self, ...)
end

function ghidorah:ai_step(dtime)
	mob_class.ai_step(self, dtime)
	kc.smash_step(self, dtime, "ghidorah:ghidorah", self._flying and FLY_SMASH or nil)
end

function ghidorah:check_standin(dtime, attach_pos)
	if self._flying then
		local depth = mob_class.check_standin(self, dtime, attach_pos)
		return depth, nil
	end
	return kc.check_standin(self, dtime, attach_pos, SWIM_DEPTH)
end

function ghidorah:step_drowning()
	return false
end

-- Hits near a head damage only that head; everything else hits the body.
function ghidorah:receive_damage(reason, damage)
	if damage > 0 and not self.dead then
		local h = self._hit_part or hit_head(self, reason)
		if h and h ~= "chest" and head_alive(self, h) then
			self._head_hp = self._head_hp or {c = HEAD_HP, l = HEAD_HP, r = HEAD_HP}
			self._head_hp[h] = self._head_hp[h] - damage
			if self._head_hp[h] <= 0 then
				sever_head(self, h, reason)
			else
				head_burst(self, h, 12)
			end
			-- (mcl_mobs plays no hurt sound and no red flash for 0 damage)
			if not self.dead then self:mob_sound("damage") end
			-- keep mcl_mobs' attacker bookkeeping (retaliation) without body damage
			return mob_class.receive_damage(self, reason, 0)
		end
	end
	return mob_class.receive_damage(self, reason, damage)
end

-- Bone overrides and the non-physical flight state are not saved with the object: re-apply.
function ghidorah:post_load_staticdata()
	mob_class.post_load_staticdata(self)
	self._head_hp = self._head_hp or {c = HEAD_HP, l = HEAD_HP, r = HEAD_HP}
	if self._flying then
		self.object:set_properties({physical = false})
	end
	self._beam_side = nil -- (its jaw overrides are gone as well)
	for _, h in ipairs(HEADS) do
		self["_aim_" .. h] = nil -- aim_head must send its override again
		if not head_alive(self, h) then apply_head_scale(self, h, 0) end
	end
end

ghidorah.gwp_penalties = table.copy(mob_class.gwp_penalties)
ghidorah.gwp_penalties.WATER = 0.0

ghidorah.ai_functions = {
	mob_class.check_attack,
	mob_class.check_pace,
}

local function hunts(self, self_pos, obj, ent)
	return is_archenemy(ent)
end

ghidorah._targeting_rules = {
	mcl_mobs.build_retaliation_target_rule({"ghidorah:ghidorah"}, false, nil),
	mcl_mobs.build_nearest_target_rule("mob", hunts, nil, nil, true),
	kc.cthulhu_rule(), -- only when he comes close (32 nodes) and is not under water
	mcl_mobs.build_nearest_target_rule("player", nil, nil, nil, true),
}

-- With him dead, Gojira and Mothra have no common enemy left: they part instead of fighting.
function ghidorah:on_die()
	kc.start_truce(self.object)
end

kc.no_knockback(ghidorah)
ghidorah.check_for_death = kaiju_core.check_for_death -- play "die", not a leftover bite
mcl_mobs.register_mob("ghidorah:ghidorah", ghidorah)

-- Egg only: no natural spawner is registered.
mcl_mobs.register_egg("ghidorah:ghidorah", S("King Ghidorah"), "#d4a62a", "#8c6a14", 0)
