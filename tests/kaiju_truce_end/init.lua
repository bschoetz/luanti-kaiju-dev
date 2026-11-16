-- What ends a truce retreat early (kaiju_core.retreat_goal / get_active_target): being
-- attacked by anyone who is not retreating as well, being stuck, and a living Ghidorah.
-- Two Gojiras and a Mothra are sent on a retreat right after they spawn (start_truce with
-- the player standing in for the dead Ghidorah; full distance 150, timeout 180 s):
--   mothra   2 s: punched by gojira2 (a truce partner): must go on
--            4 s: a Ghidorah spawns 12 nodes from her: must end and target him
--   gojira1  2 s: punched by the player: must end
--   gojira2  walks into a stone wall with kaiju_smash_blocks off: must end after about 3 s
-- Good: the last line is "RESULT ok"; any failed check is listed in it.
local function L(s) core.log("action", "[test] " .. s) end
local function tname(e)
	local a = e and e.attack
	if not a or not a:is_valid() then return "-" end
	return a:is_player() and "player" or a:get_luaentity().name:gsub(":.*", "")
end
local PUNCH = {full_punch_interval = 1.0, damage_groups = {fleshy = 5}}

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function()
		local list = {}
		for x = -1, 1 do for z = -41, -39 do for y = 9, 28 do list[#list + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(list, {name = "mcl_core:cobble"})
		player:set_pos({x = 0, y = 29, z = -40}); player:set_look_horizontal(0); player:set_look_vertical(0.05)
		core.after(2, function()
			-- gojira2's way to the wall: free of trees (the flat world has acacias, and with
			-- smashing off their leaves stop him just as well)
			local list = {}
			for x = -46, -24 do for z = 43, 57 do for y = 9, 30 do list[#list + 1] = vector.new(x, y, z) end end end
			core.bulk_set_node(list, {name = "air"})
			list = {}
			for x = -48, -47 do for z = 35, 65 do for y = 9, 30 do list[#list + 1] = vector.new(x, y, z) end end end
			core.bulk_set_node(list, {name = "mcl_core:stone"})
			local g1 = core.add_entity({x = -30, y = 8.6, z = 10}, "gojira:gojira")
			local g2 = core.add_entity({x = -30, y = 8.6, z = 50}, "gojira:gojira") -- the wall is 15 nodes west of him
			local m = core.add_entity({x = 30, y = 30, z = 30}, "mothra:mothra")
			local e1, e2, me = g1:get_luaentity(), g2:get_luaentity(), m:get_luaentity()
			kaiju_core.start_truce(player)
			local fails = {}
			local function check(ok, what) if not ok then fails[#fails + 1] = what end end
			L(("retreats started: gojira1=%s gojira2=%s mothra=%s"):format(tostring(e1._retreat_until ~= nil),
				tostring(e2._retreat_until ~= nil), tostring(me._retreat_until ~= nil)))
			check(e1._retreat_until and e2._retreat_until and me._retreat_until, "the retreats did not start")
			local stuck_end
			for t = 0, 9 do
				core.after(t, function()
					local a, b, c = g1:get_pos(), g2:get_pos(), m:get_pos()
					L(("t=%d gojira1 pos=%d,%d retreat=%s | gojira2 pos=%d,%d retreat=%s anim=%s | mothra pos=%d,%d retreat=%s target=%s"):format(t,
						a.x, a.z, tostring(e1._retreat_until ~= nil), b.x, b.z, tostring(e2._retreat_until ~= nil),
						tostring(e2._current_animation), c.x, c.z, tostring(me._retreat_until ~= nil), tname(me)))
				end)
			end
			for i = 1, 36 do
				core.after(i * 0.25, function()
					if not stuck_end and not e2._retreat_until then
						stuck_end = i * 0.25
						L(("gojira2: retreat ended after %.2f s at x=%.0f (wall at -47)"):format(stuck_end, g2:get_pos().x))
					end
				end)
			end
			core.after(2, function()
				m:punch(g2, 1.0, PUNCH, vector.new(1, 0, 0))
				g1:punch(player, 1.0, PUNCH, vector.new(-1, 0, 0))
			end)
			core.after(2.5, function()
				L(("after the punches: mothra hp=%d retreat=%s | gojira1 hp=%d retreat=%s"):format(me.health,
					tostring(me._retreat_until ~= nil), e1.health, tostring(e1._retreat_until ~= nil)))
				check(me.health < 350 and e1.health < 500, "a punch did no damage")
				check(me._retreat_until, "mothra's retreat ended on a hit from a truce partner")
				check(not e1._retreat_until, "gojira1's retreat went on after the player hit him")
			end)
			core.after(4, function()
				local p = m:get_pos()
				core.add_entity({x = p.x + 12, y = 8.6, z = p.z}, "ghidorah:ghidorah")
			end)
			core.after(6, function()
				L(("2 s after ghidorah spawned: mothra retreat=%s target=%s"):format(tostring(me._retreat_until ~= nil), tname(me)))
				check(not me._retreat_until and tname(me) == "ghidorah", "mothra did not turn on the new ghidorah")
			end)
			core.after(9.5, function()
				check(stuck_end, "gojira2 was still retreating into the wall after 9 s")
				check(g2:get_pos().x < -42, "gojira2 never reached the wall")
				L(#fails == 0 and "RESULT ok" or "RESULT FAIL: " .. table.concat(fails, "; "))
			end)
		end)
	end)
	core.after(16, function() core.request_shutdown("done") end)
end)
