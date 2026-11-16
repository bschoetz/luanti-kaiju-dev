-- Mothra under a roof: she stays below it instead of climbing into it (her ground check
-- used to start above her, inside the rock). Three closed rooms on the flat world, floor
-- at y = 8.5, walls and a roof 3 nodes thick, one wandering Mothra each for 20 s:
--   cave    64 x 64, the roof 22 above the floor (stone)
--   low     40 x 40, the roof 6 above the floor: she fits (3.6 tall), barely
--   nether  48 x 48, netherrack, a bedrock roof 28 above the floor, a 32 x 32 lava pool in
--           the middle (she starts above it)
-- Sampled every step: `inside` (her feet or the top of her body in a walkable node),
-- `escaped` (outside the room), the smallest gaps to the roof and the floor, how far she
-- rose (`low`), and her height above the lava while over the pool. FLIGHT: the clearance
-- checks' raycasts and time (kaiju_core._flight_stats); at most 40 rays per check.
-- Good: "RESULT ok".
local T = kaiju_test
local FLOOR, HEIGHT = 8.5, 3.6
local ROOMS = {
	{name = "cave", c = vector.new(0, 0, 0), half = 32, h = 22, y = 14, floor = "mcl_core:stone", wall = "mcl_core:stone", roof = "mcl_core:stone"},
	{name = "low", c = vector.new(120, 0, 0), half = 20, h = 6, y = 9.7, floor = "mcl_core:stone", wall = "mcl_core:stone", roof = "mcl_core:stone"},
	{name = "nether", c = vector.new(240, 0, 0), half = 24, h = 28, y = 22, floor = "mcl_nether:netherrack", wall = "mcl_nether:netherrack",
		roof = "mcl_core:bedrock", lava = 16},
}
local TIME = 20
local r = {}

local function build(o)
	local c, half = o.c, o.half
	local p1, p2 = vector.new(c.x - half - 1, 7, c.z - half - 1), vector.new(c.x + half + 1, 8 + o.h + 3, c.z + half + 1)
	T.fill(p1, p2, o.wall)
	T.fill(vector.new(p1.x, 8 + o.h + 1, p1.z), p2, o.roof)
	T.fill(p1, vector.new(p2.x, 8, p2.z), o.floor)
	T.fill(vector.new(c.x - half, 9, c.z - half), vector.new(c.x + half, 8 + o.h, c.z + half), "air")
	if o.lava then
		T.fill(vector.new(c.x - o.lava, 8, c.z - o.lava), vector.new(c.x + o.lava - 1, 8, c.z + o.lava - 1), "mcl_core:lava_source")
	end
end

local mothra, room, start_y
core.register_globalstep(function()
	local p = mothra and mothra:get_pos()
	if not p then return end
	local o, n = room, room.name
	local top = vector.offset(p, 0, HEIGHT, 0)
	local function walkable(q) local d = core.registered_nodes[core.get_node(q).name]; return d and d.walkable end
	if walkable(p) or walkable(top) then
		if r[n .. "_inside"] == 0 then
			T.log(("%s: inside at %s: feet in %s, top in %s"):format(n, core.pos_to_string(p, 1), core.get_node(p).name, core.get_node(top).name))
		end
		r[n .. "_inside"] = r[n .. "_inside"] + 1
	end
	if math.abs(p.x - o.c.x) > o.half + 0.5 or math.abs(p.z - o.c.z) > o.half + 0.5 or top.y > FLOOR + o.h or p.y < FLOOR then
		r[n .. "_escaped"] = true
	end
	local e = mothra:get_luaentity()
	if e and FLOOR + o.h - top.y < 1 and r[n .. "_min_roof_gap"] >= 1 then
		T.log(("%s: roof gap %.1f at %s: floor=%s cap=%s blocked=%s cramped=%s goal=%s"):format(n, FLOOR + o.h - top.y, core.pos_to_string(p, 2),
			tostring(e._floor), tostring(e._cap), tostring(e._blocked), tostring(e._cramped), e._goal and core.pos_to_string(e._goal, 1) or "-"))
	end
	r[n .. "_min_roof_gap"] = math.min(r[n .. "_min_roof_gap"], FLOOR + o.h - top.y)
	r[n .. "_min_floor_gap"] = math.min(r[n .. "_min_floor_gap"], p.y - FLOOR)
	r[n .. "_max_rise"] = math.max(r[n .. "_max_rise"], p.y - start_y)
	r[n .. "_moved"] = math.max(r[n .. "_moved"], T.flat(p, o.c))
	if o.lava and math.abs(p.x - o.c.x) < o.lava - 1 and math.abs(p.z - o.c.z) < o.lava - 1 then
		r.nether_min_lava_gap = math.min(r.nether_min_lava_gap or math.huge, p.y - FLOOR)
	end
end)

local KEYS = {"inside", "escaped", "min_roof_gap", "min_floor_gap", "max_rise", "moved"}
local function run(player, i)
	local o = ROOMS[i]
	if not o then
		local keys = {}
		for _, room_ in ipairs(ROOMS) do for _, k in ipairs(KEYS) do keys[#keys + 1] = room_.name .. "_" .. k end end
		keys[#keys + 1] = "nether_min_lava_gap"
		local s = kaiju_core._flight_stats
		if s then
			r.max_rays = s.max_rays
			T.log(("FLIGHT refreshes=%d rays=%d (%.1f per refresh, max %d) avg_us=%d max_us=%d"):format(s.refreshes, s.rays,
				s.rays / math.max(s.refreshes, 1), s.max_rays, s.total_us / math.max(s.refreshes, 1), s.max_us))
		end
		keys[#keys + 1] = "max_rays"
		T.result(r, keys, {
			{"cave_inside", {0, 0}}, {"cave_escaped", false}, {"cave_min_roof_gap", {1, 22}}, {"cave_min_floor_gap", {1, 22}}, {"cave_moved", {8, 99}},
			{"low_inside", {0, 0}}, {"low_escaped", false}, {"low_max_rise", {-1, 1}}, {"low_moved", {4, 99}},
			{"nether_inside", {0, 0}}, {"nether_escaped", false}, {"nether_min_roof_gap", {1, 28}}, {"nether_min_lava_gap", {5, 28}},
			{"max_rays", {1, 40}},
		})
		core.request_shutdown("done")
		return
	end
	local c, n = o.c, o.name
	r[n .. "_inside"], r[n .. "_escaped"], r[n .. "_min_roof_gap"], r[n .. "_min_floor_gap"] = 0, false, math.huge, math.huge
	r[n .. "_max_rise"], r[n .. "_moved"] = -math.huge, 0
	local e = o.half + 17
	core.emerge_area(vector.new(c.x - e, -8, c.z - e), vector.new(c.x + e, 60, c.z + e), function(_, _, left)
		if left > 0 then return end
		build(o)
		player:set_pos(vector.new(c.x - o.half + 2, 9, c.z - o.half + 2))
		core.after(2, function()
			room, start_y = o, o.y
			mothra = core.add_entity(vector.new(c.x, o.y, c.z), "mothra:mothra")
			core.after(TIME, function()
				local p = mothra:get_pos()
				T.log(("%s: end at %s"):format(n, p and core.pos_to_string(p, 1) or "?"))
				mothra:remove()
				mothra = nil
				run(player, i + 1)
			end)
		end)
	end)
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(3, function() run(player, 1) end)
	core.after(120, function() core.request_shutdown("timeout") end)
end)
