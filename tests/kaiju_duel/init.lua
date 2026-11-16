-- Balance: Gojira against King Ghidorah, one on one, until one of them is dead (at most
-- 140 s; run.sh caps a run at 180). Logs both once a second and ends with one "END winner=... t=... gojira=<hp>
-- ghidorah=<hp>" line. Wanted: Gojira wins narrowly (see kaiju/ghidorah/README.md, Balance).
-- They start 20, 30 or 44 nodes apart, picked at random per run ("spawned gap=..."): on flat
-- ground the fight is otherwise the same every time, and the opening (who gets how many
-- volleys in before the melee) is what differs in a real game.
local function L(s) core.log("action", "[test] " .. s) end
local LIMIT = 140

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function()
		local list = {}
		for x = -1, 1 do for z = -41, -39 do for y = 9, 22 do list[#list + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(list, {name = "mcl_core:cobble"})
		player:set_pos({x = 0, y = 23, z = -40}); player:set_look_horizontal(0); player:set_look_vertical(0.15)
		core.after(2, function()
			local gap = ({20, 30, 44})[math.random(3)]
			local g = core.add_entity({x = -gap / 2, y = 8.6, z = 15}, "gojira:gojira")
			local k = core.add_entity({x = gap / 2, y = 8.6, z = 15}, "ghidorah:ghidorah")
			L("spawned gap=" .. gap)
			local done
			local function finish(t, winner, ge, ke)
				done = true
				L(("END winner=%s t=%d gojira=%d ghidorah=%d gap=%d"):format(winner, t, math.max(ge.health, 0), math.max(ke.health, 0), gap))
				core.after(2, core.request_shutdown, "done")
			end
			for t = 1, LIMIT do
				core.after(t, function()
					if done then return end
					local ge, ke = g:get_luaentity(), k:get_luaentity()
					if not (ge and ke) then done = true; L("END winner=? (a kaiju is gone)"); core.request_shutdown("done"); return end
					local a, b = g:get_pos(), k:get_pos()
					L(("t=%d dist=%.1f | GOJIRA hp=%d anim=%s | GHIDORAH hp=%d anim=%s flying=%s beam=%s heads=%d/%d/%d"):format(t,
						math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2), ge.health, tostring(ge._current_animation),
						ke.health, tostring(ke._current_animation), tostring(ke._flying), tostring(ke._beam_time ~= nil),
						ke._head_hp and ke._head_hp.c or 120, ke._head_hp and ke._head_hp.l or 120, ke._head_hp and ke._head_hp.r or 120))
					if ge.dead and ke.dead then finish(t, "draw", ge, ke)
					elseif ke.dead then finish(t, "gojira", ge, ke)
					elseif ge.dead then finish(t, "ghidorah", ge, ke)
					elseif t == LIMIT then finish(t, "none", ge, ke) end
				end)
			end
		end)
	end)
end)
