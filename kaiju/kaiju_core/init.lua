-- kaiju_core: shared mechanics for giant mobs on top of Mineclonia's mcl_mobs.
-- Used by gojira (ground), mothra (flight), ghidorah (both) and cthulhu (ground, and the
-- flight steering under water). Every function works on
-- the mob's luaentity (`self`) and keeps its state in documented `self._*` fields.
-- See README.md for the full API.

kaiju_core = {}

-- The mob API the kaiju use: Mineclonia's mcl_mobs, or on VoxeLibre (whose older mcl_mobs
-- lacks Mineclonia's AI hooks, e.g. run_ai) the compatibility layer in vl.lua. The kaiju
-- mods take mcl_mobs from here.
local mineclonia = mcl_mobs.mob_class.run_ai ~= nil
kaiju_core.voxelibre = not mineclonia and core.get_modpath("vl_projectile") ~= nil
assert(mineclonia or kaiju_core.voxelibre,
	"kaiju_core: unsupported game, the kaiju need Mineclonia or VoxeLibre (mcl_mobs is neither)")
if kaiju_core.voxelibre then
	dofile(core.get_modpath("kaiju_core") .. "/vl.lua")
else
	kaiju_core.mcl_mobs = mcl_mobs
	function kaiju_core.mob_griefing(mob_name) return mobs_mc.is_mob_griefing_enabled(mob_name) end
	function kaiju_core.tile_drops() return mcl_vars.do_tile_drops end -- (the doTileDrops gamerule)
end
local mcl_mobs = kaiju_core.mcl_mobs
local mob_class = mcl_mobs.mob_class

-- World position of a point given relative to the mob's feet and facing, in nodes:
-- `fwd` ahead, `side` to its right-hand side (model +X), `up` above the feet.
function kaiju_core.model_point(self, fwd, side, up)
	local yaw = self.object:get_yaw()
	local f, s = core.yaw_to_dir(yaw), core.yaw_to_dir(yaw - math.pi / 2)
	return vector.offset(self.object:get_pos(), f.x * fwd + s.x * side, up, f.z * fwd + s.z * side)
end

-- Horizontal distance between two positions.
function kaiju_core.flat_dist(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

local KAIJU = {["gojira:gojira"] = true, ["mothra:mothra"] = true, ["ghidorah:ghidorah"] = true, ["cthulhu:cthulhu"] = true}

-- Is this luaentity (or nil) one of the modpack's kaiju?
function kaiju_core.is_kaiju(ent)
	return ent ~= nil and KAIJU[ent.name] == true
end

-- A targeting rule for Cthulhu, for the kaiju that fight him only when he comes close:
-- the nearest one in sight within 32 nodes (and not under water: his valid_enemy), let go
-- beyond 32 again. (The range must be a function: build_nearest_target_rule ignores a number.)
function kaiju_core.cthulhu_rule()
	return mcl_mobs.build_nearest_target_rule("mob", {"cthulhu:cthulhu"}, nil, function() return 32 end, nil)
end

------------------------------------------------------------------------
-- Animation lock: one-shot clips that mcl_mobs must not replace
------------------------------------------------------------------------

-- mcl_mobs sets walk/stand/punch on its own whenever the mob is on the ground. Call on the
-- mob definition before register_mob: while self._anim_lock (seconds, counted down by the
-- mob's own step) is positive, only "die" gets through set_animation.
function kaiju_core.lock_animations(def)
	function def:set_animation(anim, fixed_frame)
		if (self._anim_lock or 0) > 0 and anim ~= "die" then return end
		return mob_class.set_animation(self, anim, fixed_frame)
	end
end

-- Play a one-shot clip and lock the animation for `time` seconds. (A melee punch that is
-- still timing out would turn the clip into "punch".)
function kaiju_core.play(self, anim, time)
	self._anim_lock = 0
	self._punch_animation_timeout = nil
	self:set_animation(anim)
	self._anim_lock = time
end

------------------------------------------------------------------------
-- Node columns
------------------------------------------------------------------------

function kaiju_core.is_water(p)
	return core.get_item_group(core.get_node(p).name, "water") > 0
end

-- Walkable, or unknown / not loaded.
function kaiju_core.is_solid(p)
	local def = core.registered_nodes[core.get_node(p).name]
	return not def or def.walkable
end

-- The column at pos: the height of the ground or sea floor (the top of the first walkable
-- node at or below pos, or of the walkable nodes pos is inside), and of the water surface
-- above it (nil if the floor is dry). Walks the nodes, so leaves, ice or lily pads above
-- the water don't hide it, and water is not the ground. ground_y is the cheaper raycast
-- for flyers: the first pointable node from above, water and plants included.
function kaiju_core.water_column(pos)
	local is_solid, is_water = kaiju_core.is_solid, kaiju_core.is_water
	local p, n = vector.round(vector.offset(pos, 0, 1, 0)), 0
	if is_solid(p) then
		repeat p.y, n = p.y + 1, n + 1 until n > 40 or not is_solid(p)
	else
		repeat p.y, n = p.y - 1, n + 1 until n > 64 or is_solid(p)
		p.y = p.y + 1
	end
	local floor = p.y - 0.5
	if not is_water(p) then return floor, nil end
	n = 0
	repeat p.y, n = p.y + 1, n + 1 until n > 64 or not is_water(p)
	return floor, p.y - 0.5
end

------------------------------------------------------------------------
-- Node classification
------------------------------------------------------------------------

local IMMUNE_GROUPS = {"unbreakable", "indestructible", "end_portal_frame", "command_block", "fire"}

-- Nodes a kaiju never breaks: air, non-walkable (plants, liquids, fire, torches), blast
-- resistance >= 1200 (obsidian, bedrock, ...) and special groups.
function kaiju_core.is_immune(name)
	if name == "air" or name == "ignore" then return true end
	local def = core.registered_nodes[name]
	if not def or not def.walkable then return true end
	if (def._mcl_blast_resistance or 0) >= 1200 then return true end
	for _, g in ipairs(IMMUNE_GROUPS) do
		if (def.groups[g] or 0) > 0 then return true end
	end
	return false
end

-- Natural terrain (the groups Mineclonia's cave carver treats as ground). Left standing at
-- foot level so a walking kaiju climbs hills instead of tunnelling through them.
local TERRAIN_GROUPS = {"overworld_carvable", "dirt", "sand", "hardened_clay", "soil", "grass_block", "material_sand"}

function kaiju_core.is_terrain(name)
	local def = core.registered_nodes[name]
	if not def then return false end
	local groups = def.groups
	for _, g in ipairs(TERRAIN_GROUPS) do
		if (groups[g] or 0) > 0 then return true end
	end
	return false
end

------------------------------------------------------------------------
-- Smashing through the world (respects mobs_griefing and protection)
------------------------------------------------------------------------

local SMASH_INTERVAL = 0.25
local SMASH_IDLE_TICKS = 8  -- standing still without a target: smash only every 8th interval (2 s)
local DROP_CHANCE = 0.05
local TAIL_MAX_STEPS = 6    -- sweep samples per tick, bounds the cost of a fast turn
local TAIL_SEG_HALF = 1.5   -- half a segment's length, model units
local TAIL_YAW_STEP = 0.12  -- radians between sweep samples (~2 nodes at the tip)

-- Block destruction of one kind: the modpack setting `setting` (settingtypes.txt, default
-- on, read live) on top of the game's mobs_griefing (Mineclonia: gamerule for `mob_name`).
function kaiju_core.griefing_enabled(mob_name, setting)
	return core.settings:get_bool(setting, true) and kaiju_core.mob_griefing(mob_name)
end

local warned_dig = {} -- node names whose dig callback failed (logged once each)

-- floor_y: the layer it stands on (nil while swimming); only containers, beds and doors in
-- it are dug.
local function smash_node(p, floor_y, keep_terrain_to, removed, column_tops)
	local node = core.get_node(p)
	if kaiju_core.is_immune(node.name) or (p.y <= keep_terrain_to and kaiju_core.is_terrain(node.name))
			or core.is_protected(p, "") then
		return
	end
	local def = core.registered_nodes[node.name]
	local needs_dig = def.after_dig_node or (def.groups.container or 0) > 0
	-- The layer it stands on stays, so it can't sink through sandstone, ice, the Nether or
	-- the End. Exception: chests/furnaces/beds/doors. After stepping up onto rubble it walks
	-- a node higher, and would otherwise pass over a chest standing on the floor.
	if p.y == floor_y and not needs_dig then return end
	local gone
	if needs_dig then
		-- A real dig, so chests/furnaces drop their contents and doors/beds lose both halves.
		-- Some callbacks assume a player digger (e.g. mcl_beehives indexes the digger's
		-- inventory) and error out; the node is usually gone by then, so catch the error
		-- instead of crashing the server.
		local ok, res = pcall(core.dig_node, p)
		if ok then
			gone = res
		else
			gone = core.get_node(p).name ~= node.name
			if not warned_dig[node.name] then
				warned_dig[node.name] = true
				core.log("warning", "[kaiju_core] dig callback of " .. node.name .. " failed: " .. tostring(res))
			end
		end
	else
		core.remove_node(p)
		gone = true
		-- shortcut: only 5% of blocks drop, so a rampage doesn't flood the world with items
		-- tile_drops is the doTileDrops gamerule (dig_node drops check it too)
		if kaiju_core.tile_drops() and math.random() < DROP_CHANCE then
			for _, item in ipairs(core.get_node_drops(node, "")) do
				core.add_item(p, item)
			end
		end
	end
	if gone then
		removed[#removed + 1] = {pos = p, name = node.name}
		local k = p.x .. "," .. p.z
		if not column_tops[k] or p.y > column_tops[k].y then
			column_tops[k] = p
		end
	end
end

-- The server doesn't know the animated pose, so a tail is swept as boxes along the line
-- behind the mob, for every yaw it passed through since the last tick. Walking straight it
-- trails through the already cleared path, so only turning costs anything.
-- tail = {segments = {{distance behind, centre height, thickness, plate height[, side]}, ...}
-- in model units, unit = nodes per model unit, first = first segment to sweep}. With `side`
-- the segment is swept twice, offset that far to either side (two splayed tails).
local function sweep_tail(self, tail, pos, floor_y, keep_terrain_to, removed, column_tops)
	local yaw, last = self.object:get_yaw(), self._tail_yaw
	self._tail_yaw = yaw
	if not last then return end
	local diff = (yaw - last + math.pi) % (2 * math.pi) - math.pi
	if math.abs(diff) < 0.03 then return end
	local steps = math.min(math.ceil(math.abs(diff) / TAIL_YAW_STEP), TAIL_MAX_STEPS)
	local seen = {} -- neighbouring samples overlap heavily
	local unit = tail.unit
	for i = 1, steps do
		local a = last + diff * i / steps
		local dir, right = core.yaw_to_dir(a), core.yaw_to_dir(a - math.pi / 2)
		for s = tail.first or 1, #tail.segments do
			local t = tail.segments[s]
			local d, h, w, plate = t[1] * unit, t[2] * unit, t[3] * unit, t[4] * unit
			local r = math.max(w / 2, TAIL_SEG_HALF * unit) + 0.5
			for _, side in ipairs(t[5] and {t[5] * unit, -t[5] * unit} or {0}) do
			local cx, cz = pos.x - dir.x * d + right.x * side, pos.z - dir.z * d + right.z * side
			for x = math.floor(cx - r + 0.5), math.floor(cx + r + 0.5) do
				for z = math.floor(cz - r + 0.5), math.floor(cz + r + 0.5) do
					for y = math.floor(pos.y + h - w / 2 + 0.5), math.floor(pos.y + h + w / 2 + plate + 0.5) do
						local p = vector.new(x, y, z)
						local hash = core.hash_node_position(p)
						if not seen[hash] then
							seen[hash] = true
							smash_node(p, floor_y, keep_terrain_to, removed, column_tops)
						end
					end
				end
			end
			end
		end
	end
end

-- One smash pass. cfg = self._smash = {lookahead = nodes ahead, tail = see sweep_tail or nil}
function kaiju_core.smash(self, cfg)
	local pos = self.object:get_pos()
	local cb = self.collisionbox
	local dir = core.yaw_to_dir(self.object:get_yaw())
	-- Box around the body, stretched ahead in the walking direction, from one layer below
	-- the feet up to above the head. The layer it stands on stays, and so does natural
	-- terrain at foot level, so it walks on the ground and climbs hills.
	local la = cfg.lookahead or 3
	local p1 = vector.round(vector.offset(pos, cb[1] + math.min(dir.x * la, 0), cb[2] - 0.5, cb[3] + math.min(dir.z * la, 0)))
	-- Swimming it can't step up a steep shore, so it also cuts through its foot layer.
	local swimming = self.floats == 1
	local floor_y = not swimming and p1.y or nil
	local keep_terrain_to = swimming and p1.y or p1.y + 1
	-- +1 above the head: headroom for stepping up onto the next terrain layer
	local p2 = vector.round(vector.offset(pos, cb[4] + math.max(dir.x * la, 0), cb[5] + 1, cb[6] + math.max(dir.z * la, 0)))
	local removed, column_tops = {}, {}
	for x = p1.x, p2.x do
		for z = p1.z, p2.z do
			for y = p1.y, p2.y do
				smash_node(vector.new(x, y, z), floor_y, keep_terrain_to, removed, column_tops)
			end
		end
	end
	if cfg.tail then
		sweep_tail(self, cfg.tail, pos, floor_y, keep_terrain_to, removed, column_tops)
	end
	if #removed == 0 then return end

	-- Sand/gravel resting on top of the cleared columns must fall.
	for _, top in pairs(column_tops) do
		core.check_for_falling(top)
	end

	-- One dust cloud over everything that broke, textured like a random victim.
	local lo, hi = vector.copy(removed[1].pos), vector.copy(removed[1].pos)
	for _, r in ipairs(removed) do
		lo.x, lo.y, lo.z = math.min(lo.x, r.pos.x), math.min(lo.y, r.pos.y), math.min(lo.z, r.pos.z)
		hi.x, hi.y, hi.z = math.max(hi.x, r.pos.x), math.max(hi.y, r.pos.y), math.max(hi.z, r.pos.z)
	end
	core.add_particlespawner({
		amount = math.min(8 * #removed, 96), time = 0.3,
		pos = {min = vector.subtract(lo, 0.5), max = vector.add(hi, 0.5)},
		vel = {min = vector.new(-3, 0, -3), max = vector.new(3, 5, 3)},
		acc = vector.new(0, -9.81, 0),
		exptime = {min = 0.6, max = 1.4},
		size = {min = 1, max = 3},
		collisiondetection = true,
		node = {name = removed[math.random(#removed)].name},
	})
	local loudest = removed[math.random(#removed)]
	local sounds = core.registered_nodes[loudest.name].sounds
	if sounds and sounds.dug then
		core.sound_play(sounds.dug, {pos = loudest.pos, gain = 2.0, max_hear_distance = 48}, true)
	end
end

-- Call from ai_step: smashes every SMASH_INTERVAL (if mobs_griefing and the
-- kaiju_smash_blocks setting allow it for `mob_name`), throttled while the mob idles without a target.
function kaiju_core.smash_step(self, dtime, mob_name)
	if self.dead or not kaiju_core.griefing_enabled(mob_name, "kaiju_smash_blocks") then return end
	self._smash_timer = (self._smash_timer or 0) + dtime
	if self._smash_timer < SMASH_INTERVAL then return end
	self._smash_timer = 0
	-- Standing still and not turning there is nothing new to break. Only without a target
	-- (hunting, an obstacle also stops it dead and must go at once), and it still looks
	-- every SMASH_IDLE_TICKS in case it paced into a wall.
	local v, yaw = self.object:get_velocity(), self.object:get_yaw()
	local idle = not self.attack and v.x * v.x + v.z * v.z < 0.01
		and math.abs(yaw - (self._smash_yaw or math.huge)) < 0.01
	self._smash_yaw = yaw
	self._smash_idle = idle and (self._smash_idle or 0) + 1 or 0
	if self._smash_idle % SMASH_IDLE_TICKS == 0 then
		kaiju_core.smash(self, self._smash or {})
	end
end

------------------------------------------------------------------------
-- Bulldozer: walk straight at the target when the pathfinder gives up
------------------------------------------------------------------------

-- The pathfinder rarely finds room for a huge body in forests or towns. If the mob hasn't
-- closed in on the target for STUCK_TIME, it bulldozes straight at it for BULLDOZE_TIME
-- (smash() clears the way). Call update_bulldoze from attack_melee, gopath from the gopath
-- override and end_bulldoze from attack_end.
local STUCK_TIME = 3.0
local BULLDOZE_TIME = 6.0
local STANDOFF = 2.0 -- nodes kept between the two bodies in melee (they need about one to stop)

-- mcl_mobs' melee walks to the target's own position, and nothing pushes two kaiju apart,
-- so they ended up standing inside each other. Is the mob as close to its target as the
-- two collision boxes allow (plus STANDOFF, but never beyond its reach)? Only for a target
-- at body height: under a flyer or a player on a tower it walks on. And only within reach:
-- the bite is measured in 3D, so a target at chest height can be out of reach at that gap.
-- Then the second return value is true, and gopath walks straight on to get below it.

-- The horizontal gap, centre to centre, a mob keeps to a target with collision box `tcb`.
function kaiju_core.standoff_gap(self, tcb)
	return math.min(self.collisionbox[4] + tcb[4] + STANDOFF, self.reach - 0.5)
end

local function at_standoff(self)
	local target = self.attack
	local tp = target and target:is_valid() and target:get_pos()
	if not tp then return false end
	local p, cb, tcb = self.object:get_pos(), self.collisionbox, target:get_properties().collisionbox
	if tp.y - p.y >= cb[5] or p.y - tp.y >= tcb[5] then return false end
	if kaiju_core.flat_dist(p, tp) >= kaiju_core.standoff_gap(self, tcb) then return false end
	if vector.distance(p, tp) > self.reach then return false, true end
	return true
end

-- Stuck detection: has the distance to where the mob wants to be (`dist`) not shrunk by a
-- node for STUCK_TIME? Being within `near` of it never counts as stuck.
local function stuck(self, dtime, dist, near)
	self._stuck_timer = (self._stuck_timer or 0) + dtime
	if dist <= near or not self._best_dist or dist < self._best_dist - 1 then
		self._best_dist = dist
		self._stuck_timer = 0
		return false
	end
	return self._stuck_timer >= STUCK_TIME
end

function kaiju_core.update_bulldoze(self, dtime, attach_pos, target_pos)
	if at_standoff(self) and self:is_navigating() then
		self:cancel_navigation()
		self:halt_in_tracks()
	end
	if self._bulldoze_time then
		self._bulldoze_time = self._bulldoze_time - dtime
		if self._bulldoze_time <= 0 then
			self._bulldoze_time = nil
			self:cancel_navigation()
		end
		return
	end
	if stuck(self, dtime, kaiju_core.flat_dist(attach_pos, target_pos), self.reach + 1) then
		self._bulldoze_time = BULLDOZE_TIME
		self._best_dist = nil
		self._stuck_timer = 0
		self:cancel_navigation()
		self:go_to_stupidly(target_pos, self.pursuit_bonus)
	end
end

-- While bulldozing, ignore the pathfinder and walk straight at the target. Also for the
-- last steps below a target above the ground, where the pathfinder finds no node to go to.
function kaiju_core.gopath(self, target, speed_bonus, ...)
	local standoff, below = at_standoff(self)
	if standoff then
		return true -- (only melee asks for a path while there is a target)
	end
	if self._bulldoze_time or below then
		self:cancel_navigation()
		self:go_to_stupidly(target, speed_bonus)
		return true
	end
	return mob_class.gopath(self, target, speed_bonus, ...)
end

function kaiju_core.end_bulldoze(self)
	self._best_dist = nil -- the next target starts its own stuck detection
	self._stuck_timer = 0
	if self._bulldoze_time then
		-- otherwise roaming stays straight-line and the next target inherits the rest
		self._bulldoze_time = nil
		self:cancel_navigation()
	end
end

------------------------------------------------------------------------
-- Water: wade up to chest depth, swim (head above water) when deeper
------------------------------------------------------------------------

-- Mineclonia switches any mob touching water to swim physics (slow water_velocity) and
-- lets floats=1 mobs bob on the surface. For a giant that's wrong: up to `swim_depth` it
-- wades on the bottom with land physics at full speed; only deeper does it swim, and
-- buoyancy (floats=1 while deep) holds head and shoulders above the surface.
function kaiju_core.check_standin(self, dtime, attach_pos, swim_depth)
	local depth, liquidtype = mob_class.check_standin(self, dtime, attach_pos)
	if liquidtype == "water" then
		if depth < swim_depth then
			liquidtype = nil
			self.floats = 0
		else
			self.floats = 1
		end
	end
	return depth, liquidtype
end

------------------------------------------------------------------------
-- Knockback
------------------------------------------------------------------------

-- With knockback_resistance 1.0 mcl_mobs turns a punch or projectile into a zero knockback
-- vector and *sets* it as the velocity, so every hit would stop a kaiju dead. Call on the
-- mob definition before register_mob (damage still applies).
function kaiju_core.no_knockback(def)
	def.knockback_resistance = 1.0
	def.knock_back = false
	def.projectile_knockback = function() end
end

------------------------------------------------------------------------
-- Death
------------------------------------------------------------------------

-- mcl_mobs' set_animation turns any animation into "punch" while a melee punch animation
-- is still timing out, so a kaiju killed mid-bite never played "die". Assign as the mob's
-- check_for_death: clears that timeout when the hit is fatal. It also stops the mob:
-- mcl_mobs lets a dying mob walk on, so a kaiju killed mid-stride slid through its whole
-- "die" clip.
function kaiju_core.check_for_death(self, reason, damage)
	if damage > 0 and self.health <= 0 then
		self._punch_animation_timeout = nil
	end
	local was_dead = self.dead
	local died = mob_class.check_for_death(self, reason, damage)
	if self.dead and not was_dead then
		self:halt_in_tracks(true)
	end
	return died
end

------------------------------------------------------------------------
-- Flight
------------------------------------------------------------------------

local CLEARANCE_STEP = 4       -- ground sample spacing along the path to the goal
local CLEARANCE_SAMPLES = 12   -- at most this many steps (longer paths get wider spacing)
local DEATH_FALL_TIME = 2.5    -- default: land within this (Mothra's body is removed 3.5 s after death)
local DEATH_FALL_MAX = 30      -- fall speed cap (nodes/s)

-- Height of the first pointable node (ground, liquid, but also leaves/plants) below pos
-- (scans up to 64 nodes down).
function kaiju_core.ground_y(pos)
	local from = vector.offset(pos, 0, 2, 0)
	for pointed in core.raycast(from, vector.offset(pos, 0, -64, 0), false, true) do
		if pointed.type == "node" then
			return pointed.above.y - 0.5
		end
	end
	return pos.y - 64
end

-- Keep self._goal at least `min_clearance` above the terrain along the whole path from the
-- mob to the goal (sampled every CLEARANCE_STEP nodes, checked 4x a second). fly_velocity
-- climbs on the spot while the mob is below this floor (self._floor), so it never cuts
-- through a hill or wall between the samples' ends.
function kaiju_core.keep_clearance(self, self_pos, dtime, min_clearance)
	local goal = self._goal
	if not goal then return end
	self._floor_timer = (self._floor_timer or 0) - dtime
	if self._floor_timer <= 0 or not self._floor then
		self._floor_timer = 0.25
		local from = math.max(self_pos.y, goal.y) + 30
		local n = math.min(CLEARANCE_SAMPLES, math.ceil(vector.distance(self_pos, goal) / CLEARANCE_STEP))
		local floor = -math.huge
		for i = 0, n do
			local p = vector.add(self_pos, vector.multiply(vector.subtract(goal, self_pos), n > 0 and i / n or 0))
			floor = math.max(floor, kaiju_core.ground_y(vector.new(p.x, from, p.z)))
		end
		self._floor = floor + min_clearance
	end
	goal.y = math.max(goal.y, self._floor)
end

-- Steer the velocity smoothly towards self._goal at self._goal_speed (or default_speed).
-- No gravity, no node collisions: meant for physical = false flyers whose goals are kept
-- above ground by keep_clearance. Returns the wanted velocity (for facing).
function kaiju_core.fly_velocity(self, dtime, self_pos, default_speed)
	local want = vector.zero()
	local goal = self._goal
	if goal then
		local speed = self._goal_speed or default_speed
		if self._floor and self_pos.y < self._floor - 2 then
			-- higher terrain ahead (or below): climb on the spot first, then cross
			want = vector.new(0, math.min(speed, (self._floor - self_pos.y) * 2), 0)
		else
			local d = vector.subtract(goal, self_pos)
			local dist = vector.length(d)
			if dist > 0.5 then
				want = vector.multiply(d, math.min(speed, dist * 2) / dist)
			end
		end
	end
	local v = self.object:get_velocity()
	local k = math.min(1, dtime * 1.5)
	self.object:set_velocity(vector.add(v, vector.multiply(vector.subtract(want, v), k)))
	return want
end

-- Dead flyer: become physical and drop fast enough to land before mcl_mobs removes the body.
-- fall_time: land within this many seconds (default DEATH_FALL_TIME); keep it below the
-- mob's die animation length + 0.5 s, when mcl_mobs removes the body.
function kaiju_core.death_fall(self, self_pos, fall_time)
	if not self._falling then
		self.object:set_properties({physical = true}) -- drop to the ground instead of through it
		local drop = self_pos.y - kaiju_core.ground_y(self_pos)
		self._falling = math.min(DEATH_FALL_MAX, math.max(8, drop / (fall_time or DEATH_FALL_TIME)))
	end
	self.object:set_velocity(vector.new(0, -self._falling, 0))
end

------------------------------------------------------------------------
-- Hit boxes: invisible objects that pass hits on a body part to the kaiju
------------------------------------------------------------------------

-- The server's raycast (arrows) only finds objects whose position is within 5 nodes of the
-- ray, and a kaiju's position is at its feet: everything above the knees was arrow-proof.
-- So the high parts carry an invisible object of their own that passes punches and
-- projectile hits on to the owner; `owner._hit_part` holds the part's name during the call.

local function hitbox_owner(self)
	local owner = self._owner and self._owner:is_valid() and self._owner:get_luaentity()
	return owner and not owner.dead and owner
end

local function pass_on(self, hit)
	local owner = hitbox_owner(self)
	if not owner then return end
	owner._hit_part = self._part.name
	hit(self._owner)
	owner._hit_part = nil
end

core.register_entity("kaiju_core:hitbox", {
	initial_properties = {
		visual = "sprite", textures = {"blank.png"}, physical = false, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0}, selectionbox = {-2, -2, -2, 2, 2, 2},
	},
	_hittable_by_projectile = true, -- mcl_bows
	on_activate = function(self)
		self.object:set_armor_groups({immortal = 1})
	end,
	on_step = function(self)
		local owner = hitbox_owner(self)
		if not owner then
			self.object:remove()
			return
		end
		-- (set_pos sends a packet to every client even if nothing moved)
		local pos = self._part.pos(owner)
		if not (self._pos and vector.equals(pos, self._pos)) then
			self._pos = pos
			self.object:set_pos(pos)
		end
	end,
	on_punch = function(self, puncher, tflp, caps, dir)
		pass_on(self, function(obj) obj:punch(puncher, tflp, caps, dir) end)
		return true
	end,
	-- called by mcl_util.deal_damage (projectiles)
	deal_damage = function(self, damage, reason)
		pass_on(self, function(obj) mcl_util.deal_damage(obj, damage, reason) end)
		return true
	end,
})

-- Call every step (run_ai/ai_step): (re)creates the mob's hit boxes.
-- parts = {{name = "chest", pos = function(self) -> world position of the box centre,
-- box = selection box (default 4x4x4)}, ...}. The objects are kept in `self._hitbox_<name>`:
-- top-level fields, because mcl_mobs drops ObjectRefs from staticdata only there (inside a
-- table they would break saving). The boxes themselves are not saved.
function kaiju_core.ensure_hitboxes(self, parts)
	for _, part in ipairs(parts) do
		local key = "_hitbox_" .. part.name
		if not (self[key] and self[key]:is_valid()) then
			local obj = core.add_entity(part.pos(self), "kaiju_core:hitbox")
			local ent = obj and obj:get_luaentity()
			if ent then
				ent._owner, ent._part = self.object, part
				if part.box then obj:set_properties({selectionbox = part.box}) end
				self[key] = obj
			end
		end
	end
end

------------------------------------------------------------------------
-- Truce: after a Ghidorah's death the Gojiras and the Mothras move apart
------------------------------------------------------------------------

-- Without him Mothra hunts Gojira, so the allies would turn on each other over his body.
-- Instead each species leaves as a group, in opposite directions, far enough to be out of
-- each other's view range. (A table so that tests can shorten the walk.)
kaiju_core.truce = {
	radius = 200,   -- nodes around the dead Ghidorah: who takes part
	distance = 150, -- nodes each kaiju moves, so the species end up 300 apart
	timeout = 180,  -- seconds after which a retreat ends wherever the kaiju is
	arrive = 4,     -- nodes (horizontal) from the goal that count as arrived
}

-- Call when a Ghidorah dies (on_die). Does nothing unless a Gojira and a Mothra are loaded
-- within the radius and no other living Ghidorah is. The retreat state is three plain
-- numbers per kaiju (`_retreat_x`, `_retreat_z`, `_retreat_until` in game time), so it
-- survives an unload; a retreat whose time ran out while unloaded is simply over.
function kaiju_core.start_truce(dead)
	local t = kaiju_core.truce
	local groups = {["gojira:gojira"] = {}, ["mothra:mothra"] = {}}
	for obj in core.objects_inside_radius(dead:get_pos(), t.radius) do
		local ent = obj ~= dead and obj:get_luaentity()
		if ent and not ent.dead then
			if ent.name == "ghidorah:ghidorah" then return end -- the fight goes on
			local group = groups[ent.name]
			if group then group[#group + 1] = obj end
		end
	end
	local gojiras, mothras = groups["gojira:gojira"], groups["mothra:mothra"]
	if #gojiras == 0 or #mothras == 0 then return end
	local function centroid(group)
		local x, z = 0, 0
		for _, obj in ipairs(group) do
			local p = obj:get_pos()
			x, z = x + p.x / #group, z + p.z / #group
		end
		return x, z
	end
	-- the Gojiras leave along the line from the Mothras to them, the Mothras the other way;
	-- everyone gets the same offset, so a group keeps its formation
	local gx, gz = centroid(gojiras)
	local mx, mz = centroid(mothras)
	local dx, dz = gx - mx, gz - mz
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 0.5 then
		local a = math.random() * 2 * math.pi
		dx, dz, len = math.cos(a), math.sin(a), 1
	end
	dx, dz = dx / len * t.distance, dz / len * t.distance
	local deadline = core.get_gametime() + t.timeout
	for sign, group in pairs({[1] = gojiras, [-1] = mothras}) do
		for _, obj in ipairs(group) do
			local p, ent = obj:get_pos(), obj:get_luaentity()
			ent._retreat_x, ent._retreat_z, ent._retreat_until = p.x + sign * dx, p.z + sign * dz, deadline
			ent._retreat_attack_id = ent._last_attack_id or 0 -- (hits up to now don't end it)
			ent._best_dist, ent._stuck_timer = nil, 0         -- the retreat's own stuck detection
		end
	end
end

local function end_retreat(self)
	self._retreat_x, self._retreat_z, self._retreat_until, self._retreat_attack_id = nil, nil, nil, nil
	self._best_dist, self._stuck_timer = nil, 0
	self:cancel_navigation() -- (a walker's straight-line goal)
end

-- Was the mob hit since its retreat started? Hits from kaiju that are retreating as well
-- (the truce partners: a gust or a flame that was already under way) don't count.
local function attacked(self)
	local id = self._last_attack_id or 0
	if id == self._retreat_attack_id then return false end
	self._retreat_attack_id = id
	local by = self._last_attacker
	local ent = by and by:is_valid() and by:get_luaentity()
	return not (ent and ent._retreat_until)
end

-- The point (at the mob's own height) a retreating kaiju heads for, or nil if it is not
-- retreating. Ends the retreat on arrival, after the timeout, when the mob was attacked,
-- and, for a walker (one that passes its step's `dtime`), when it is stuck: no closer to
-- the goal for STUCK_TIME, e.g. at a cliff it may not break through.
function kaiju_core.retreat_goal(self, dtime)
	if not self._retreat_until then return nil end
	local p = self.object:get_pos()
	local dist = kaiju_core.flat_dist(p, {x = self._retreat_x, z = self._retreat_z})
	if core.get_gametime() >= self._retreat_until or dist < kaiju_core.truce.arrive
			or attacked(self) or (dtime and stuck(self, dtime, dist, 0)) then
		end_retreat(self)
		return nil
	end
	return vector.new(self._retreat_x, p.y, self._retreat_z)
end

-- Assign as the mob's get_active_target: a retreating kaiju has no target, so check_attack
-- ends a running attack and starts none. Except for a living Ghidorah: he ends the retreat.
function kaiju_core.get_active_target(self, self_pos)
	local target = mob_class.get_active_target(self, self_pos)
	if self._retreat_until then
		local ent = target and target:is_valid() and target:get_luaentity()
		if not (ent and ent.name == "ghidorah:ghidorah" and not ent.dead) then return nil end
		end_retreat(self)
	end
	return target
end
