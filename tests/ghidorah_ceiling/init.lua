-- Ghidorah and roofs, and where he lands. Block smashing is off (kaiju_smash_blocks), so
-- nothing clears his way. Three phases, each with a fresh Ghidorah and the survival
-- player 60 nodes away (beyond FAR_TARGET: he wants to fly):
--   low     under a roof 18 above the floor (he is 15 tall and needs 21 to take off): he
--           walks instead of taking off through the rock.
--   cavern  a roof 40 above the floor, and between him and the player a section only 16
--           high: he takes off, stays below the roof, finds the section too low to fly
--           through, lands and walks under it; he does not keep taking off again.
--   forest  open sky. He starts under a canopy of leaves 17 above the ground (leaves are no
--           roof: he takes off through them). The player stands in a forest of low trees,
--           in a treeless patch of 17 x 17; 12 nodes from the player is a 10 x 10 clearing.
--           Both have a netherrack floor. He lands in one of them (`forest_clearing_dist`:
--           how far from the clearing's centre), not on the trees below him.
-- Sampled every step: `flew`, take-offs, `inside` (his feet or the top of his body in a
-- walkable node), the highest point of his body; in "forest" where he touched down.
-- Good: "RESULT ok".
local T = kaiju_test
T.keep_players_alive()
-- (never dead: a bite and three beams can take 20 HP in one step)
core.register_on_player_hpchange(function(player, change) return math.max(change, 1 - player:get_hp()) end, true)
local TREE = core.registered_nodes["mcl_trees:tree_oak"] and "mcl_trees:tree_oak" or "mcl_core:tree"
local LEAVES = core.registered_nodes["mcl_trees:leaves_oak"] and "mcl_trees:leaves_oak" or "mcl_core:leaves"
local FLOOR, HEIGHT, HALF = 8.5, 15, 2.6
local r = {}

local function tree_nodes(p1, p2) return T.count(TREE, p1, p2) + T.count(LEAVES, p1, p2) end

local PHASES = {
	{name = "low", z = 0, time = 15, build = function(z)
		T.fill(vector.new(-12, 27, z - 20), vector.new(72, 29, z + 20), "mcl_core:stone")
	end},
	{name = "cavern", z = 200, time = 30, build = function(z)
		T.fill(vector.new(-25, 49, z - 35), vector.new(95, 51, z + 35), "mcl_core:stone")
		T.fill(vector.new(25, 25, z - 35), vector.new(45, 48, z + 35), "mcl_core:stone")
	end},
	{name = "forest", z = 400, time = 30, build = function(z)
		-- the canopy over his start, with trunks in it (or the leaves decay), none above him
		T.fill(vector.new(-8, 26, z - 8), vector.new(8, 27, z + 8), LEAVES)
		for x = -8, 8, 4 do for _, dz in ipairs({-3, 3}) do core.set_node(vector.new(x, 26, z + dz), {name = TREE}) end end
		-- trees every 4 nodes, 30 around the player (60, z), low enough for him to see the
		-- player over them; none close to the player, and the clearing at (48, z)
		for x = 28, 92, 4 do for tz = z - 32, z + 32, 4 do
			local player = math.abs(x - 60) <= 8 and math.abs(tz - z) <= 8
			local clearing = math.abs(x - 48) <= 6 and math.abs(tz - z) <= 6
			if not player and not clearing then
				T.fill(vector.new(x - 1, 11, tz - 1), vector.new(x + 1, 12, tz + 1), LEAVES)
				T.fill(vector.new(x, 9, tz), vector.new(x, 11, tz), TREE)
			end
		end end
		-- (netherrack: no "terrain" for the smashing rules, but ground to land on)
		T.fill(vector.new(43, 8, z - 5), vector.new(53, 8, z + 5), "mcl_nether:netherrack")
		T.fill(vector.new(52, 8, z - 8), vector.new(68, 8, z + 8), "mcl_nether:netherrack")
	end},
}

local ghidorah, phase, spot, was_flying, logged
core.register_globalstep(function()
	local pl = core.get_connected_players()[1]
	if pl and spot and vector.distance(pl:get_pos(), spot) > 0.5 then pl:set_pos(spot) end
	local e = ghidorah and ghidorah:get_luaentity()
	if not e then return end
	local n, p = phase.name, ghidorah:get_pos()
	local function walkable(q) local d = core.registered_nodes[core.get_node(q).name]; return d and d.walkable end
	if walkable(vector.offset(p, 0, 1, 0)) or walkable(vector.offset(p, 0, HEIGHT - 0.5, 0)) then r[n .. "_inside"] = r[n .. "_inside"] + 1 end
	r[n .. "_max_top"] = math.max(r[n .. "_max_top"], p.y + HEIGHT)
	local flying = e._flying == true
	if flying and not was_flying then
		r[n .. "_takeoffs"] = r[n .. "_takeoffs"] + 1
		T.log(("%s: take-off at %s"):format(n, core.pos_to_string(p, 1)))
	elseif was_flying and not flying then
		T.log(("%s: touch-down at %s"):format(n, core.pos_to_string(p, 1)))
		if n == "forest" and not r.forest_landing_trees then
			r.forest_landing_trees = tree_nodes(vector.round(vector.offset(p, -HALF, 0.5, -HALF)), vector.round(vector.offset(p, HALF, HEIGHT, HALF)))
			local q = vector.round(p) -- (he touches down up to 1.5 above the ground)
			while q.y > p.y - 4 and not walkable(q) do q.y = q.y - 1 end
			r.forest_landing_node = core.get_node(q).name
			r.forest_clearing_dist = T.flat(p, vector.new(48, 0, phase.z))
		end
	end
	was_flying = flying
	r[n .. "_flying"] = flying
	local now = core.get_gametime()
	if now ~= logged and now % 3 == 0 then
		logged = now
		T.log(("%s: pos=%s flying=%s land=%s target=%s"):format(n, core.pos_to_string(p, 1), tostring(flying), tostring(e._land), T.name_of(e.attack)))
	end
end)

local function run(player, i)
	phase = PHASES[i]
	if not phase then
		T.result(r, {"low_takeoffs", "low_inside", "low_max_top", "low_walked", "cavern_takeoffs", "cavern_inside", "cavern_max_top",
			"cavern_flying", "forest_takeoffs", "forest_inside", "forest_landing_trees", "forest_landing_node", "forest_clearing_dist"}, {
			{"low_takeoffs", {0, 0}}, {"low_inside", {0, 0}}, {"low_walked", {10, 99}},
			{"cavern_takeoffs", {1, 2}}, {"cavern_inside", {0, 0}}, {"cavern_max_top", {0, 47.5}}, {"cavern_flying", false},
			{"forest_takeoffs", {1, 9}}, {"forest_landing_trees", {0, 0}}, {"forest_landing_node", "mcl_nether:netherrack"},
		})
		core.request_shutdown("done")
		return
	end
	local n, z = phase.name, phase.z
	r[n .. "_takeoffs"], r[n .. "_inside"], r[n .. "_max_top"] = 0, 0, 0
	core.emerge_area(vector.new(-48, -8, z - 56), vector.new(120, 70, z + 56), function(_, _, left)
		if left > 0 then return end
		T.fill(vector.new(-40, 9, z - 48), vector.new(110, 60, z + 48), "air") -- (the flat world's trees)
		phase.build(z)
		spot = vector.new(60, FLOOR + 0.5, z)
		player:set_pos(spot)
		core.after(2, function()
			was_flying = false
			local start = vector.new(0, FLOOR + 0.1, z)
			ghidorah = core.add_entity(start, "ghidorah:ghidorah")
			-- the phase's time runs from when he has his target (Mineclonia: sometimes
			-- only after several seconds)
			local waited = 0
			local function wait(fn)
				local e = ghidorah:get_luaentity()
				waited = waited + 0.25
				if (e and e.attack) or waited > 20 then fn() else core.after(0.25, wait, fn) end
			end
			wait(function() core.after(phase.time, function()
				local p = ghidorah:get_pos() -- (nil: he left the loaded blocks, through a roof)
				r[n .. "_walked"] = p and T.flat(p, start)
				T.log(("%s: end at %s"):format(n, p and core.pos_to_string(p, 1) or "?"))
				ghidorah:remove()
				ghidorah = nil
				core.after(1, function() run(player, i + 1) end)
			end) end)
		end)
	end)
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(3, function() run(player, 1) end)
	core.after(165, function() core.request_shutdown("timeout") end)
end)
