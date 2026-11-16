-- Ghidorah smashes in the air. A survival player stands 15 nodes up on a realm barrier
-- (not pointable: for him the player is in the air), so he circles it 12 nodes above the
-- ground for 45 s. Across the circle: a cobble wall 25 high, a band of oak leaves with
-- trunks, and a ridge of stone 8 high.
-- Smashing on: he flies through the wall and the leaves (the clearance ignores what he may
-- break) and tears them down, but climbs over the stone (natural terrain stays).
-- Other runs: KAIJU_TEST_CONF='kaiju_smash_blocks = false' (nothing breaks, he climbs over
-- the wall) and KAIJU_TEST_CONF='kaiju_test_protect = true' (the wall is protected: it
-- stays and he climbs over it; the leaves still fall).
-- Logged too: the time of a smash pass in the air. Good: "RESULT ok".
local T = kaiju_test
T.keep_players_alive()
local SMASH = core.settings:get_bool("kaiju_smash_blocks", true)
local PROTECT = core.settings:get_bool("kaiju_test_protect", false)
local CENTRE = vector.new(0, 23.5, 60)
local WALL = {vector.new(-26, 9, 60), vector.new(-8, 33, 61)}
local LEAVES = {vector.new(8, 19, 58), vector.new(26, 26, 62)}
local RIDGE = {vector.new(-3, 9, 68), vector.new(3, 16, 84)}
local TREE, LEAF
core.register_on_mods_loaded(function()
	TREE = core.registered_nodes["mcl_trees:tree_oak"] and "mcl_trees:tree_oak" or "mcl_core:tree"
	LEAF = core.registered_nodes["mcl_trees:leaves_oak"] and "mcl_trees:leaves_oak" or "mcl_core:leaves"
	if PROTECT then
		local is_protected = core.is_protected
		function core.is_protected(p, name)
			return (p.x >= WALL[1].x and p.x <= WALL[2].x and p.z >= WALL[1].z and p.z <= WALL[2].z) or is_protected(p, name)
		end
	end
	local smash = kaiju_core.smash
	kaiju_core._test_smash = {n = 0, us = 0, max = 0}
	function kaiju_core.smash(self, cfg)
		local t0 = core.get_us_time()
		smash(self, cfg)
		local s, us = kaiju_core._test_smash, core.get_us_time() - t0
		if self._flying then s.n, s.us, s.max = s.n + 1, s.us + us, math.max(s.max, us) end
	end
end)

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.emerge_area(vector.new(-40, 0, 0), vector.new(40, 60, 100), function(_, _, left)
		if left > 0 then return end
		T.fill(WALL[1], WALL[2], "mcl_core:cobble")
		T.fill(LEAVES[1], LEAVES[2], LEAF)
		T.fill(vector.new(8, 22, 60), vector.new(26, 22, 60), TREE)
		core.set_node(vector.new(0, 23, 60), {name = "mcl_core:realm_barrier"})
		T.fill(RIDGE[1], RIDGE[2], "mcl_core:stone")
		local wall0, leaves0, stone0 = T.count("mcl_core:cobble", WALL[1], WALL[2]), T.count(LEAF, LEAVES[1], LEAVES[2]), T.count("mcl_core:stone", RIDGE[1], RIDGE[2])
		player:set_pos(CENTRE)
		core.after(3, function()
			local k = core.add_entity(vector.new(0, 8.6, 5), "ghidorah:ghidorah")
			local r, t, done = {wall_y = 0, ridge_y = 0}, 0, false
			core.register_globalstep(function(dtime)
				local e, p = k:get_luaentity(), k:get_pos()
				if done or not e then return end
				player:set_pos(CENTRE)
				e.health = 600
				if math.floor(t / 3) ~= math.floor((t + dtime) / 3) then
					T.log(("t=%d pos=%s flying=%s land=%s blocked=%s target=%s floor=%s"):format(t + dtime, core.pos_to_string(vector.round(p)),
						tostring(e._flying), tostring(e._land), tostring(e._blocked), T.name_of(e.attack), tostring(e._floor)))
				end
				t = t + dtime
				if p.x >= WALL[1].x and p.x <= WALL[2].x and math.abs(p.z - 60.5) < 3 then r.wall_y = math.max(r.wall_y, p.y) end
				if math.abs(p.x) < 2 and p.z >= RIDGE[1].z and p.z <= RIDGE[2].z then r.ridge_y = math.max(r.ridge_y, p.y) end
				if t >= 45 then
					done = true
					local s = kaiju_core._test_smash
					T.log(("smash=%s protect=%s flying=%s air smash passes=%d avg_us=%d max_us=%d"):format(tostring(SMASH), tostring(PROTECT),
						tostring(e._flying), s.n, s.us / math.max(s.n, 1), s.max))
					r.wall_removed = wall0 - T.count("mcl_core:cobble", WALL[1], WALL[2])
					r.leaves_removed = leaves0 - T.count(LEAF, LEAVES[1], LEAVES[2])
					r.stone_removed = stone0 - T.count("mcl_core:stone", RIDGE[1], RIDGE[2])
					local through, over = {{"wall_removed", {30, 950}}, {"wall_y", {15, 27}}}, {{"wall_removed", {0, 0}}, {"wall_y", {40, 60}}}
					local expect = (SMASH and not PROTECT) and through or over
					expect[#expect + 1] = {"leaves_removed", SMASH and {10, 760} or {0, 0}}
					expect[#expect + 1] = {"stone_removed", {0, 0}}
					expect[#expect + 1] = {"ridge_y", {26, 60}}
					T.result(r, {"wall_removed", "wall_y", "leaves_removed", "stone_removed", "ridge_y"}, expect)
					core.request_shutdown("done")
				end
			end)
		end)
	end)
end)
