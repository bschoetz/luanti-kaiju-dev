-- Shared helpers for the scenarios (tests/README.md). run.sh links this folder into every
-- test world as the mod `kaiju_test`; a scenario that uses it lists it in its `depends`.
kaiju_test = {}
local T = kaiju_test

function T.log(s) core.log("action", "[test] " .. s) end

-- VoxeLibre 0.92.4 ignores `mobs_spawn = false` (vl_tuning never applies a false default to
-- its doMobSpawning gamerule): set the gamerule, so animals don't wander into the scenes.
if core.get_modpath("vl_tuning") and not core.settings:get_bool("mobs_spawn", true) then
	core.register_on_mods_loaded(function() vl_tuning.setting("gamerule:doMobSpawning"):set(false) end)
end

-- Horizontal distance.
function T.flat(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) end

-- "gojira" for a gojira:gojira object, "player" for a player, "nil" for none.
function T.name_of(obj)
	local ent = obj and obj:is_valid() and obj:get_luaentity()
	return ent and ent.name:gsub(".*:", "") or tostring(obj and obj:is_valid() and obj:is_player() and "player" or nil)
end

-- Survival scenarios: top up every living player's HP each step.
function T.keep_players_alive()
	core.register_globalstep(function()
		for _, pl in ipairs(core.get_connected_players()) do if pl:get_hp() > 0 then pl:set_hp(20) end end
	end)
end

-- The Cthulhu scenarios' sea: water from (-22, -13, 14) to (22, 8, 58), surface at y = 8.5,
-- and the spot at the centre of its floor where he is spawned (his home).
T.SEA_HOME = vector.new(0, -13.5, 36)
T.SEA_SURFACE = 8.5

-- Fills p1..p2 (default: that sea) with water on a stone floor (the flat mapgen has caves)
-- and clears 30 nodes of air above it (trees), then calls done. (VoxelManip: 45k set_node
-- calls overflow mcl_redstone's event queue.)
function T.sea(done, p1, p2)
	p1, p2 = p1 or vector.new(-22, -13, 14), p2 or vector.new(22, 8, 58)
	local top = vector.offset(p2, 0, 30, 0)
	core.emerge_area(vector.offset(p1, -16, -1, -48), vector.offset(top, 16, 0, 16), function(_, _, left)
		if left > 0 then return end
		local vm = VoxelManip()
		local area = VoxelArea(vm:read_from_map(vector.offset(p1, 0, -1, 0), top))
		local data = vm:get_data()
		local water, stone, air = core.get_content_id("mcl_core:water_source"), core.get_content_id("mcl_core:stone"), core.CONTENT_AIR
		for z = p1.z, p2.z do for y = p1.y - 1, top.y do for x = p1.x, p2.x do
			data[area:index(x, y, z)] = y < p1.y and stone or y <= p2.y and water or air
		end end end
		vm:set_data(data)
		vm:write_to_map(true)
		done()
	end)
end

-- Records core.remove_node calls (what kaiju_core's smashing uses). Returns a function:
-- removed(pos) is the number of nodes removed within 12 nodes of pos (the game removes
-- nodes of its own elsewhere: leaves, plants), removed(true) forgets them all.
function T.count_removed()
	local list, orig = {}, core.remove_node
	core.remove_node = function(p) list[#list + 1] = vector.copy(p); return orig(p) end
	return function(pos)
		if pos == true then list = {}; return 0 end
		local n = 0
		for _, p in ipairs(list) do if vector.distance(p, pos) <= 12 then n = n + 1 end end
		return n
	end
end

-- The end of a scenario: logs `VALUES k=v ...` for the keys of r, checks them and logs
-- `RESULT ok` or `RESULT FAIL: <reasons>`. expect is a list of {key, want}: want = true
-- or false (exactly that), a string (tostring equals it), {min, max} (a number in that
-- range), or "set" (not nil). A missing value always fails.
function T.result(r, keys, expect)
	local s = "VALUES"
	for _, k in ipairs(keys) do
		local v = r[k]
		s = s .. " " .. k .. "=" .. (type(v) == "number" and ("%.1f"):format(v) or tostring(v))
	end
	T.log(s)
	local fails = {}
	for _, e in ipairs(expect) do
		local k, want = e[1], e[2]
		local v = r[k]
		local ok
		if want == "set" then
			ok = v ~= nil
		elseif type(want) == "table" then
			ok = type(v) == "number" and v >= want[1] and v <= want[2]
		elseif type(want) == "string" then
			ok = tostring(v) == want
		else
			ok = v == want
		end
		if not ok then
			fails[#fails + 1] = ("%s=%s (want %s)"):format(k, tostring(v),
				type(want) == "table" and want[1] .. ".." .. want[2] or tostring(want))
		end
	end
	T.log(#fails == 0 and "RESULT ok" or "RESULT FAIL: " .. table.concat(fails, "; "))
end

-- The real-terrain scenarios (test.conf: mg_name = v7, fixed_map_seed = 7): a sandy beach
-- that slopes into an ocean. OCEAN_SHORE is a spot on the beach; the water is to its
-- south-west, 13 deep 35 nodes out and deeper beyond.
T.OCEAN_SHORE = vector.new(-1095, 0, 441)

-- Height of the top walkable node of a column (from 40 above the water level down).
function T.column(x, z)
	local wl = tonumber(core.get_mapgen_setting("water_level")) or 1
	local p = vector.new(math.floor(x + 0.5), wl + 40, math.floor(z + 0.5))
	local function solid() local d = core.registered_nodes[core.get_node(p).name]; return d and d.walkable end
	while p.y > wl - 70 and not solid() do p.y = p.y - 1 end
	return p.y
end

-- A spot to stand on in that column.
function T.on_ground(x, z) return vector.new(x, T.column(x, z) + 1.5, z) end

-- Generates the terrain 130 nodes around OCEAN_SHORE, then calls done.
function T.ocean(done)
	local c = T.OCEAN_SHORE
	core.emerge_area(vector.new(c.x - 130, -60, c.z - 130), vector.new(c.x + 130, 45, c.z + 130), function(_, _, left)
		if left == 0 then done() end
	end)
end
