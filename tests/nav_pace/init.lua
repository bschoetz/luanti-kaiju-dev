-- Navigation course (tests/README.md §Navigation courses): block smashing is off, no
-- target. Gojira paces all the time (pace_chance 1) inside a pen of cobble walls, 3 high,
-- 21 x 21 nodes inside; most pace goals lie near or behind a wall.
-- Good: RESULT ok. He wanders (moved: path length) without running into the walls: on
-- VoxeLibre a kaiju blocked by a wall hops, so max_y stays at ground level (8.5).
local T = kaiju_test
local W1, W2 = vector.new(-11, 9, -11), vector.new(11, 11, 11)
T.nav_course({
	area = {vector.new(-24, 0, -30), vector.new(24, 0, 24)},
	build = function()
		T.fill(W1, W2, "mcl_core:cobble")
		T.fill(vector.new(-10, 9, -10), vector.new(10, 11, 10), "air")
	end,
	mob = "gojira:gojira", spawn = vector.new(0, 8.6, 0), player = vector.new(0, 9, -20), time = 40, no_target = true,
	setup = function(e) e.pace_chance, e.pace_interval, e.pace_width = 1, 0, 14 end,
	blocks = {{"mcl_core:cobble", W1, W2}},
	keys = {"moved", "max_y", "removed", "nav_max_us"},
	expect = {{"moved", {10, 1000}}, {"max_y", {8.4, 8.9}}, {"removed", {0, 0}}},
})
