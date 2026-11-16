-- Navigation course (tests/README.md §Navigation courses): block smashing is off. A forest
-- (a trunk every 3 nodes under a closed canopy, 33 x 23 nodes) stands between Gojira and
-- the player, with a clear 7-wide lane off the direct line. Built once he has his target:
-- the canopy hides the player.
-- Good: RESULT ok. He reaches the player through the lane or around the forest; no trunk
-- or leaf is gone.
local T = kaiju_test
-- oak: Mineclonia's names, else VoxeLibre's
local TREE = core.registered_nodes["mcl_trees:tree_oak"] and "mcl_trees:tree_oak" or "mcl_core:tree"
local LEAVES = core.registered_nodes["mcl_trees:leaves_oak"] and "mcl_trees:leaves_oak" or "mcl_core:leaves"
local F1, F2 = vector.new(-16, 9, -9), vector.new(16, 16, 13)
T.nav_course({
	area = {vector.new(-30, 0, -28), vector.new(30, 0, 34)},
	late_build = true,
	build = function()
		T.fill(vector.new(-16, 13, -9), F2, LEAVES)
		for x = -15, 15, 3 do
			for z = -8, 12, 3 do T.fill(vector.new(x, 9, z), vector.new(x, 14, z), TREE) end
		end
		T.fill(vector.new(6, 9, -9), vector.new(12, 16, 13), "air")
	end,
	mob = "gojira:gojira", spawn = vector.new(0, 8.6, 24), player = vector.new(0, 9, -18), time = 45,
	setup = function(e) e._breath_cooldown = 1e9 end,
	blocks = {{TREE, F1, F2}, {LEAVES, F1, F2}},
	keys = {"reached", "removed", "max_y", "moved", "nav_max_us"},
	expect = {{"reached", {0, 45}}, {"removed", {0, 0}}},
})
