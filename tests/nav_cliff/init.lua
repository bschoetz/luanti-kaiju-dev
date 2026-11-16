-- Navigation course (tests/README.md §Navigation courses): block smashing is off. The
-- player stands on a stone plateau 6 nodes high; the only way up is a 7-wide stair of
-- 1-node steps off the direct line.
-- Good: RESULT ok. Gojira takes the stair (top: seconds until he stands on the plateau)
-- and reaches the player; no stone is gone.
local T = kaiju_test
local P1, P2 = vector.new(-30, 9, -30), vector.new(30, 14, 0)
T.nav_course({
	area = {vector.new(-30, 0, -30), vector.new(30, 0, 26)},
	build = function(player)
		T.fill(P1, vector.new(30, 14, -6), "mcl_core:stone")
		for z = -5, 0 do T.fill(vector.new(4, 9, z), vector.new(10, 9 - z, z), "mcl_core:stone") end
		player:set_pos(vector.new(0, 15, -16))
	end,
	mob = "gojira:gojira", spawn = vector.new(0, 8.6, 14), player = vector.new(0, 9, -16), time = 50,
	setup = function(e) e._breath_cooldown = 1e9 end,
	blocks = {{"mcl_core:stone", P1, P2}},
	sample = function(r, e, p, t) if not r.top and p.y >= 14.4 then r.top = t end end,
	keys = {"top", "reached", "removed", "max_y", "moved", "nav_max_us"},
	expect = {{"top", {0, 50}}, {"reached", {0, 50}}, {"removed", {0, 0}}},
})
