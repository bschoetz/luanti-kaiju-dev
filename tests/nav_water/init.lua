-- Navigation course (tests/README.md §Navigation courses): block smashing is off. Gojira
-- swims in a pool 31 x 31 nodes wide and 22 deep with vertical stone walls. The only way
-- out is a 7-wide ramp of 1-node steps, off the direct line to the player.
-- Good: RESULT ok. He swims to the ramp, walks out (ashore: seconds until he is on dry
-- ground) and reaches the player; no stone is gone.
local T = kaiju_test
local S1, S2 = vector.new(-18, -15, 8), vector.new(18, 8, 42)
T.nav_course({
	area = {vector.new(-30, 0, -20), vector.new(30, 0, 46)},
	build = function()
		T.fill(S1, S2, "mcl_core:stone")
		T.fill(vector.new(-15, -13, 10), vector.new(15, 8, 40), "mcl_core:water_source")
		for z = 10, 30 do T.fill(vector.new(4, -13, z), vector.new(10, 17 - z, z), "mcl_core:stone") end
	end,
	mob = "gojira:gojira", spawn = vector.new(0, -2, 30), player = vector.new(0, 9, -6), time = 60,
	setup = function(e) e._breath_cooldown = 1e9 end,
	blocks = {{"mcl_core:stone", S1, S2}},
	sample = function(r, e, p, t)
		if not r.ashore and (e._immersion_depth or 0) == 0 and p.y >= 8.4 then r.ashore = t end
	end,
	keys = {"ashore", "reached", "removed", "max_y", "moved", "nav_max_us"},
	expect = {{"ashore", {0, 60}}, {"reached", {0, 60}}, {"removed", {0, 0}}},
})
