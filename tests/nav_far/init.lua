-- Navigation course (tests/README.md §Navigation courses): open ground, the player 60
-- nodes away (beyond the 24 nodes VoxeLibre's path search covers at once).
-- Good: RESULT ok. Gojira crosses without stalling: speed (nodes/s until he is in reach)
-- is at least 5 of his 6.
local T = kaiju_test
T.nav_course({
	area = {vector.new(-20, 0, -24), vector.new(20, 0, 60)},
	build = function() end,
	mob = "gojira:gojira", spawn = vector.new(0, 8.6, 48), player = vector.new(0, 9, -12), time = 20,
	setup = function(e) e._breath_cooldown = 1e9 end,
	keys = {"reached", "speed", "removed", "moved", "nav_max_us"},
	expect = {{"reached", {0, 20}}, {"speed", {5, 8}}},
})
