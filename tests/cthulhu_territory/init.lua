-- Cthulhu's territory: neutral while the player is outside it, wakes for an intruder on
-- the beach, gives up after 20 s on land and goes home, lets go of a target beyond the
-- leash. Ends with a VALUES and a RESULT line (see tests/README.md). The grab is switched off here
-- (an attached player can't be moved by the scenario); cthulhu_grab covers it.
local T = kaiju_test
local L, flat, name_of = T.log, T.flat, T.name_of
local HOME = T.SEA_HOME
local OUTSIDE, BEACH, BEYOND = vector.new(0, 9.5, -16), vector.new(0, 9.5, 4), vector.new(0, 9.5, -40)

T.keep_players_alive()


core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	T.sea(function()
		player:set_pos(OUTSIDE); player:set_look_horizontal(0)
		core.after(3, function()
			local c = core.add_entity(vector.offset(HOME, 0, 0.1, 0), "cthulhu:cthulhu")
			local e = c:get_luaentity()
			e._grab_cooldown = 1e9
			local data = core.deserialize(e:get_staticdata())
			local r = {saved_home = data._home and flat(data._home, HOME) < 0.1 and math.abs(data._home.y - HOME.y) < 0.1}
			L(("spawned home=%s saved_home=%s home_depth=%.1f"):format(core.pos_to_string(vector.new(e._home), 1),
				data._home and core.pos_to_string(vector.new(data._home), 1) or "nil", e._home_depth))
			local t, phase, mark = 0, "A", 0
			local function go(name) phase, mark = name, t; L("PHASE " .. name) end
			local function tick()
				e = c:get_luaentity()
				if not e then L("RESULT FAIL: cthulhu is gone"); core.request_shutdown("done"); return end
				t = t + 0.5
				local p = c:get_pos()
				local target = e.attack ~= nil
				if t % 1 == 0 then
					L(("t=%d %s pos=%.0f,%.1f,%.0f home_dist=%.1f sea=%s depth=%.1f target=%s anim=%s land_time=%.1f returning=%s valid_enemy=%s floor=%s surface=%s hp=%d"):format(
						t, phase, p.x, p.y, p.z, flat(p, HOME), tostring(e._at_sea == true), e._immersion_depth or 0, tostring(target),
						tostring(e._current_animation), e._land_time or 0, tostring(e._returning == true), tostring(e:valid_enemy()), tostring(e._floor_y), tostring(e._surface_y), e.health))
				end
				if phase == "A" then                 -- player 52 nodes from home
					r.neutral_outside = (r.neutral_outside ~= false) and not target
					if t >= 6 then r.asleep = e._current_animation == "dormant"; player:set_pos(BEACH); go("B") end
				elseif phase == "B" then             -- player on the beach, 32 from home
					if target and not r.woke then r.woke = t - mark end
					if e._current_animation == "rise" then r.rise = true end
					if e._current_animation == "roar" then r.roar = true end
					-- on dry land: out of the water and south of the sea's edge (z = 13.5)
					if target and (e._immersion_depth or 0) < 1 and p.z < 13.5 then r.ashore = true end
					if e._returning then
						r.gave_up_land_time = e._land_time_seen
						player:set_pos(OUTSIDE); go("C")
					end
					e._land_time_seen = e._land_time
				elseif phase == "C" then             -- he walks home, the player is outside again
					if not e._returning and not target and flat(p, HOME) < 6 and e._current_animation == "dormant" then
						r.home_again = t - mark
						player:set_pos(BEACH); go("D")
					end
				elseif phase == "D" then             -- intruder again, then beyond the leash
					-- (8 s: he is at the shore by then, in the water or out of it)
					if target and t - mark >= 8 then player:set_pos(BEYOND); go("E") end
				elseif phase == "E" then
					if not target and not r.leash_drop then r.leash_drop = t - mark end
					if r.leash_drop and flat(p, HOME) < 6 then r.home_after_leash = t - mark; go("END") end
				end
				if phase == "END" or t >= 150 then
					T.result(r, {"saved_home", "neutral_outside", "asleep", "woke", "rise", "roar", "ashore", "gave_up_land_time", "home_again",
						"leash_drop", "home_after_leash"}, {
						{"saved_home", true}, {"neutral_outside", true}, {"asleep", true}, {"woke", {0, 2}}, {"rise", true}, {"roar", true},
						{"ashore", true}, {"gave_up_land_time", {19, 20.6}}, {"home_again", {1, 30}}, {"leash_drop", {0, 1.5}},
						{"home_after_leash", {1, 30}}})
					core.request_shutdown("done")
					return
				end
				core.after(0.5, tick)
			end
			core.after(0.5, tick)
		end)
	end)
end)
