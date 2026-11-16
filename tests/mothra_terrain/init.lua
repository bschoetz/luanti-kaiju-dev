-- Three phases, one Mothra each:
--   A (terrain): a 36-high stone wall between her and her goal; she must climb over it.
--   B (sight):   a husk in a walled 3x3 cell; she must regain sight instead of circling blind.
--   C (death):   killed ~50 nodes up; the body must reach the ground before removal.
local function L(s) core.log("action", "[test] " .. s) end
local function fill(p1, p2, name)
	local list = {}
	for x = p1.x, p2.x do for y = p1.y, p2.y do for z = p1.z, p2.z do list[#list + 1] = vector.new(x, y, z) end end end
	core.bulk_set_node(list, {name = name})
end
local function flat(a, b) return vector.distance(vector.new(a.x, 0, a.z), vector.new(b.x, 0, b.z)) end
local function every(t0, n, dt, fn) for i = 1, n do core.after(t0 + i * dt, fn, i * dt) end end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	player:set_pos({x = -45, y = 9, z = 0}); player:set_look_horizontal(-math.pi / 2)
	-- A: wall x -20..20, z 0..2, y 9..44 (top surface 44.5)
	local a
	core.after(2, function()
		fill(vector.new(-20, 9, 0), vector.new(20, 44, 2), "mcl_core:stone")
		a = core.add_entity({x = 0, y = 26, z = -25}, "mothra:mothra")
	end)
	core.after(3, function()
		local e = a:get_luaentity()
		e._goal, e._goal_speed, e._wander_timer = vector.new(0, 26, 25), 5, 60
		L("A goal (0,26,25) behind the wall, wall top y=44.5")
	end)
	local inside, min_over = 0, math.huge
	every(3, 40, 0.5, function(t)
		local p = a:get_pos(); if not p then return end
		local n = core.get_node(vector.round(vector.offset(p, 0, 1, 0))).name
		if n == "mcl_core:stone" then inside = inside + 1 end
		if p.z > -3 and p.z < 5 then min_over = math.min(min_over, p.y - 44.5) end
		L(("A t=%.1f pos=(%.1f,%.1f,%.1f) node=%s"):format(t, p.x, p.y, p.z, n))
	end)
	core.after(24, function()
		L(("A summary: samples_inside_wall=%d min_feet_above_wall_top_while_crossing=%s"):format(inside, tostring(min_over)))
		a:remove()
	end)

	-- B: husk in a cell, walls y 9..16, interior x -1..1, z 39..41
	local b, h
	local blind, seen, near = 0, 0, 0
	core.after(24, function()
		fill(vector.new(-2, 9, 38), vector.new(2, 16, 42), "mcl_core:stone")
		fill(vector.new(-1, 9, 39), vector.new(1, 16, 41), "air")
		h = core.add_entity({x = 0, y = 8.6, z = 40}, "mobs_mc:husk")
		b = core.add_entity({x = 0, y = 30, z = 40}, "mothra:mothra")
	end)
	every(25, 40, 0.5, function(t)
		local e, he = b:get_luaentity(), h:get_luaentity()
		if not e or not he then L(("B t=%.1f husk %s"):format(t, he and "alive" or "gone")); return end
		local bp, hp = b:get_pos(), h:get_pos()
		local vis = e:target_visible(bp, h)
		if e.attack == h then
			if vis then seen = seen + 1 else blind = blind + 1 end
			if flat(bp, hp) < 6 then near = near + 1 end
		end
		L(("B t=%.1f target=%s visible=%s flat=%.1f y=%.1f anim=%s husk_hp=%d"):format(t,
			e.attack == h and "husk" or tostring(e.attack and "other" or "-"), tostring(vis), flat(bp, hp), bp.y, tostring(e._current_animation), he.health))
	end)
	core.after(46, function()
		L(("B summary: targeted+visible=%d targeted+blind=%d targeted+within6=%d husk=%s"):format(seen, blind, near, h:get_luaentity() and ("hp " .. h:get_luaentity().health) or "dead"))
		b:remove(); if h:is_valid() then h:remove() end
	end)

	-- C: die ~50 nodes above the flat ground (y 8.5)
	local c
	core.after(46, function() c = core.add_entity({x = 0, y = 60, z = -40}, "mothra:mothra") end)
	core.after(47, function()
		L(("C killed at y=%.1f"):format(c:get_pos().y))
		mcl_util.deal_damage(c, 1000, {type = "generic"})
	end)
	every(47, 20, 0.25, function(t)
		local p = c:get_pos()
		L(("C t=%.2f %s"):format(t, p and ("y=%.1f"):format(p.y) or "removed"))
	end)
	core.after(53, function() core.request_shutdown("done") end)
end)
