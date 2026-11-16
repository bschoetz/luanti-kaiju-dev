-- Cthulhu on real terrain: a mapgen v7 beach and ocean (seed 7). He is spawned on the
-- beach, as with the egg, and must pick a home in deep water close enough for the beach to
-- be in his territory; sleep there in the idol pose although the sea floor slopes, without
-- wearing it away; wake with the rise clip for a player on the beach; come out on dry
-- land; grab the player without holding him inside the ground; and go home and sleep again
-- when the player is gone. Ends with a VALUES and a RESULT line (see tests/README.md).
local T = kaiju_test
local L, flat = T.log, T.flat
local SHORE = T.OCEAN_SHORE

T.keep_players_alive()
local removed = T.count_removed(p)

local function solid(p)
	local def = core.registered_nodes[core.get_node(p).name]
	return not def or def.walkable
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function() T.ocean(function()
		local spot = T.on_ground(SHORE.x, SHORE.z)
		local c = core.add_entity(vector.offset(spot, 0, -0.4, 0), "cthulhu:cthulhu")
		local e = c:get_luaentity()
		local home = vector.new(e._home)
		local r = {home_dist = flat(home, spot), home_depth = e._home_depth}
		-- on the line from his home through the spot he was spawned on: 46 nodes from home
		-- (in his territory, 48) and 90 (beyond his leash, 72)
		local inland = vector.normalize(vector.new(spot.x - home.x, 0, spot.z - home.z))
		local beach = T.on_ground(home.x + inland.x * 46, home.z + inland.z * 46)
		local far = T.on_ground(home.x + inland.x * 90, home.z + inland.z * 90)
		L(("spawned at %s home=%s home_depth=%.1f beach=%s (%.0f from home) far=%s"):format(core.pos_to_string(spot, 1),
			core.pos_to_string(home, 1), e._home_depth, core.pos_to_string(beach, 1), flat(beach, home), core.pos_to_string(far, 1)))
		player:set_pos(far)
		c:set_pos(vector.offset(home, 0, 0.1, 0)) -- (skip the walk home)
		local t, phase, mark = 0, "settle", 0
		local held, buried = false, 0
		r.buried = 0
		local function go(name) phase, mark = name, t; L("PHASE " .. name) end
		local function tick()
			e = c:get_luaentity()
			if not e then L("RESULT FAIL: cthulhu is gone"); core.request_shutdown("done"); return end
			t = t + 0.25
			local dt, p, pp = t - mark, c:get_pos(), player:get_pos()
			local target = e.attack ~= nil
			local asleep = not target and e._current_animation == "dormant" and flat(p, home) < 6
			local attached = player:get_attach() ~= nil
			if attached then
				held = true
				-- (the grip passes through nodes on its way; staying inside one is the bug)
				buried = (solid(pp) or solid(vector.offset(pp, 0, 1.5, 0))) and buried + 1 or 0
				r.buried = math.max(r.buried, buried)
			elseif held then
				held, buried, r.grabs = false, 0, (r.grabs or 0) + 1
			end
			if t % 1 == 0 then
				L(("t=%d %s pos=%.1f,%.1f,%.1f home_dist=%.1f sea=%s depth=%.1f floor=%s surface=%s target=%s anim=%s land_time=%.1f returning=%s removed=%d | player=%.1f,%.1f,%.1f attached=%s in=%s"):format(
					t, phase, p.x, p.y, p.z, flat(p, home), tostring(e._at_sea == true), e._immersion_depth or 0, tostring(e._floor_y), tostring(e._surface_y),
					tostring(target), tostring(e._current_animation), e._land_time or 0, tostring(e._returning == true), removed(p),
					pp.x, pp.y, pp.z, tostring(attached), core.get_node(vector.offset(pp, 0, 1.5, 0)).name))
			end
			if phase == "settle" then
				if asleep or dt >= 20 then r.settled = asleep; removed(true); go("asleep") end
			elseif phase == "asleep" then            -- 10 s at home, nobody near
				r.asleep = (r.asleep ~= false) and asleep
				r.rest_above_floor = math.max(r.rest_above_floor or 0, p.y - (e._floor_y or p.y))
				if dt >= 10 then r.idle_removed = removed(p); player:set_pos(beach); go("beach") end
			elseif phase == "beach" then             -- the player on the beach
				if target and not r.woke then r.woke = dt end
				if e._current_animation == "rise" then r.rise = true end
				-- on dry land, as his land timer counts it
				if target and (e._immersion_depth or 0) < 1 and not r.ashore then r.ashore = dt end
				if (r.ashore and r.grabs and not attached) or dt >= 70 then player:set_pos(far); go("leave") end
			elseif phase == "leave" then             -- the player beyond the leash
				if not target and not r.let_go then r.let_go = dt end
				if r.let_go and asleep then r.home_again = dt; go("END") end
				if dt >= 60 then go("END") end
			end
			if phase == "END" then
				T.result(r, {"home_dist", "home_depth", "settled", "asleep", "rest_above_floor", "idle_removed", "woke", "rise", "ashore",
					"grabs", "buried", "let_go", "home_again"}, {
					{"home_dist", {8, 48.1}}, {"home_depth", {15, 64}}, {"settled", true}, {"asleep", true}, {"idle_removed", {0, 0}},
					{"woke", {0, 2}}, {"rise", true}, {"ashore", {1, 60}}, {"grabs", {1, 9}}, {"buried", {0, 4}}, {"let_go", {0, 2}},
					{"home_again", {1, 60}}})
				core.request_shutdown("done")
				return
			end
			core.after(0.25, tick)
		end
		core.after(3, tick)
	end) end)
end)
