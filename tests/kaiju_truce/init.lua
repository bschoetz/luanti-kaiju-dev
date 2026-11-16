-- Truce after Ghidorah's death: the Gojiras and the Mothras within 200 nodes of him move
-- apart in opposite directions (kaiju_core.start_truce) instead of fighting each other.
-- Ghidorah, two Gojiras and a Mothra brawl for 10 s, then he is killed.
-- The retreat distance is shortened to 40 nodes (kaiju_core.truce.distance, 150 in the
-- game) so that nobody leaves the active blocks around the player.
-- A third Gojira joins 1.5 s before the kill, 46 nodes out, so he is still following a
-- pathfinder path towards Ghidorah when the truce starts: he must turn round at once
-- (stale waypoints used to take him to the corpse first).
-- Good: the last line is "RESULT ok"; any failed check is listed in it.
local function L(s) core.log("action", "[test] " .. s) end
local DIST = 40
local function tname(e)
	local a = e and e.attack
	if not a or not a:is_valid() then return "-" end
	return a:is_player() and "player" or a:get_luaentity().name:gsub(":.*", "")
end
local function flat(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	kaiju_core.truce.distance = DIST
	core.after(2, function()
		local list = {}
		for x = -1, 1 do for z = -41, -39 do for y = 9, 28 do list[#list + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(list, {name = "mcl_core:cobble"})
		player:set_pos({x = 0, y = 29, z = -40}); player:set_look_horizontal(0); player:set_look_vertical(0.05)
		core.after(2, function()
			local k = core.add_entity({x = 0, y = 8.6, z = 20}, "ghidorah:ghidorah")
			local objs = {
				{"gojira1", core.add_entity({x = -22, y = 8.6, z = 10}, "gojira:gojira"), 1},
				{"gojira2", core.add_entity({x = -22, y = 8.6, z = 30}, "gojira:gojira"), 1},
				{"mothra", core.add_entity({x = 22, y = 30, z = 20}, "mothra:mothra"), -1},
			}
			L("spawned")
			local fails, start, arrived, axis, sep0 = {}, {}, {}, nil, nil
			local function check(ok, what) if not ok then fails[#fails + 1] = what end end
			local function separation(at) -- Gojira centroid to Mothra, horizontally
				local function pos(i) return at and at[objs[i][1]] or objs[i][2]:get_pos() end
				return flat(vector.multiply(vector.add(pos(1), pos(2)), 0.5), pos(3))
			end
			local function report(t)
				local parts = {}
				for _, o in ipairs(objs) do
					local e, p = o[2]:get_luaentity(), o[2]:get_pos()
					-- (gone: unloaded, it wandered out of the active blocks after its retreat)
					parts[#parts + 1] = e and ("%s hp=%d target=%s pos=%d,%d retreat=%s"):format(o[1], e.health, tname(e),
						p.x, p.z, tostring(e._retreat_until ~= nil)) or o[1] .. " gone"
				end
				L(("t=%d %s"):format(t, table.concat(parts, " | ")))
			end
			for t = 1, 9 do core.after(t, report, t) end
			core.after(8.5, function()
				-- on the Gojiras' side of Ghidorah, out of fire breath range (32)
				local kp, mp = k:get_pos(), objs[3][2]:get_pos()
				local c = vector.multiply(vector.add(objs[1][2]:get_pos(), objs[2][2]:get_pos()), 0.5)
				local dir = vector.normalize(vector.new(c.x - mp.x, 0, c.z - mp.z))
				local late = core.add_entity(vector.new(kp.x + dir.x * 46, 8.6, kp.z + dir.z * 46), "gojira:gojira")
				objs[4] = {"gojira3", late, 1}
			end)
			core.after(10, function()
				for _, o in ipairs(objs) do start[o[1]] = o[2]:get_pos() end
				sep0 = separation()
				local ke = k:get_luaentity()
				ke.health = 0
				ke:check_for_death({type = "generic"}, 1)
				local e1 = objs[1][2]:get_luaentity()
				-- gojira3: was he on a pathfinder path, and does he ever come closer to the corpse?
				local e3, corpse = objs[4][2]:get_luaentity(), k:get_pos()
				local d0 = flat(start.gojira3, corpse)
				local closest = d0
				-- (VoxeLibre has no pathfinder: there he walks a straight line, stupid_target)
				local on_path = e3.waypoints or e3.pathfinding_context or kaiju_core.voxelibre and e3.stupid_target
				L(("gojira3 at the kill: target=%s on a path=%s, %.0f nodes from ghidorah"):format(tname(e3),
					tostring(on_path ~= nil and on_path ~= false), d0))
				check(on_path, "gojira3 was not on a path at the kill (rerun)")
				for i = 1, 40 do
					core.after(i * 0.25, function()
						closest = math.min(closest, flat(objs[4][2]:get_pos() or start.gojira3, corpse))
						if i == 40 then
							L(("gojira3 came at most %.1f nodes closer to the corpse"):format(d0 - closest))
							check(d0 - closest < 3, ("gojira3 walked %.0f nodes towards the corpse"):format(d0 - closest))
						end
					end)
				end
				check(e1._retreat_until ~= nil, "no retreat started")
				if not e1._retreat_until then return end
				-- the common axis: from Gojira's start to his goal
				axis = vector.normalize(vector.new(e1._retreat_x - start.gojira1.x, 0, e1._retreat_z - start.gojira1.z))
				local sd = e1:get_staticdata()
				check(sd:find("_retreat_until", 1, true) and sd:find("_retreat_x", 1, true), "retreat state not in staticdata")
				L(("ghidorah killed: dead=%s separation=%.0f axis=%.2f,%.2f staticdata has the retreat=%s"):format(
					tostring(ke.dead), sep0, axis.x, axis.z, tostring(sd:find("_retreat_until", 1, true) ~= nil)))
			end)
			for t = 11, 34 do
				core.after(t, function()
					report(t)
					for _, o in ipairs(objs) do
						local e = o[2]:get_luaentity()
						if not e then -- (unloaded)
						elseif e._retreat_until then
							check(tname(e) == "-", ("%s has a target at t=%d"):format(o[1], t))
						else
							-- arrived: from here on the normal AI runs (it wanders, the test distance is short)
							arrived[o[1]] = arrived[o[1]] or o[2]:get_pos()
						end
					end
				end)
			end
			core.after(35, function()
				if not axis then L("RESULT FAIL: " .. table.concat(fails, "; ")); return end
				for _, o in ipairs(objs) do
					check(arrived[o[1]], o[1] .. " still retreating")
					arrived[o[1]] = arrived[o[1]] or o[2]:get_pos() or start[o[1]]
					local d = vector.subtract(arrived[o[1]], start[o[1]])
					local along = (d.x * axis.x + d.z * axis.z) * o[3]
					L(("%s moved %.0f along its direction (%.0f sideways) until its retreat ended"):format(o[1], along,
						math.abs(d.x * axis.z - d.z * axis.x)))
					check(along > DIST - 8, o[1] .. " moved only " .. math.floor(along))
				end
				local sep = separation(arrived)
				L(("separation %.0f -> %.0f (retreat distance %d each)"):format(sep0, sep, DIST))
				check(sep > sep0 + 2 * DIST - 12, "separation grew only to " .. math.floor(sep))
				L(#fails == 0 and "RESULT ok" or "RESULT FAIL: " .. table.concat(fails, "; "))
			end)
		end)
	end)
	core.after(42, function() core.request_shutdown("done") end)
end)
