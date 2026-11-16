-- Cthulhu in the water: sleeps on the sea floor (not targetable), rises until head and
-- shoulders are out for a target at the shore, regenerates 2 HP/s half submerged but only
-- 5 s after a hit, takes 1.5x damage on dry land, dives away below 25 % HP and comes back
-- at 70 %, or after the flee timeout whatever his HP. Ends with a VALUES and a RESULT line
-- (see tests/README.md). The grab is switched off.
local T = kaiju_test
local L, flat, name_of = T.log, T.flat, T.name_of
local HOME = T.SEA_HOME
local OUTSIDE, SHORE, INLAND = vector.new(0, 9.5, -16), vector.new(0, 9.5, 12), vector.new(0, 9.5, -2)
local SURFACE, HP = T.SEA_SURFACE, 550

T.keep_players_alive()


core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	T.sea(function()
		player:set_pos(OUTSIDE); player:set_look_horizontal(0)
		core.after(3, function()
			local c = core.add_entity(vector.offset(HOME, 0, 0.1, 0), "cthulhu:cthulhu")
			local e = c:get_luaentity()
			e._grab_cooldown = 1e9
			local t, phase, mark, r = 0, "A", 0, {sea_walk = 0}
			local function go(name) phase, mark = name, t; L("PHASE " .. name) end
			local function hit(n) return mcl_util.deal_damage(c, n, {type = "mob", source = player, direct = player}) end
			local function tick()
				e = c:get_luaentity()
				if not e then L("RESULT FAIL: cthulhu is gone"); core.request_shutdown("done"); return end
				t = t + 0.5
				local p, dt = c:get_pos(), t - mark
				local target = e.attack ~= nil
				-- in sea mode he swims or holds still, never "walk" (his own animation lock and
				-- gopath must be in effect)
				if e._at_sea and target and e._current_animation == "walk" then r.sea_walk = r.sea_walk + 1 end
				if t % 1 == 0 then
					L(("t=%d %s pos=%.0f,%.1f,%.0f head_out=%.1f sea=%s depth=%.1f target=%s anim=%s hp=%.1f fleeing=%s valid_enemy=%s player=%s in=%s"):format(
						t, phase, p.x, p.y, p.z, p.y + 13 - SURFACE, tostring(e._at_sea == true), e._immersion_depth or 0, tostring(target),
						tostring(e._current_animation), e.health, tostring(e._fleeing == true), tostring(e:valid_enemy()),
						core.pos_to_string(player:get_pos(), 1), core.get_node(player:get_pos()).name))
				end
				if phase == "A" then                 -- asleep on the sea floor
					if dt >= 5 then
						r.asleep_y, r.asleep_targetable = p.y, e:valid_enemy()
						player:set_pos(SHORE); go("B")
					end
				elseif phase == "B" then             -- target at the water's edge: he surfaces
					if dt >= 12 then
						r.head_out, r.risen_targetable, r.risen_sea = p.y + 13 - SURFACE, e:valid_enemy(), e._at_sea == true
						r.hit_water = e.health
						hit(100)
						r.hit_water = r.hit_water - e.health
						r.hp0 = e.health
						go("C")
					end
				elseif phase == "C" then             -- regeneration: none for 5 s after the hit, then 2 HP/s
					if dt == 4 then r.regen_4s = e.health - r.hp0 end
					if dt == 15 then
						r.regen_15s = e.health - r.hp0
						player:set_pos(INLAND); go("D")
					end
				elseif phase == "D" then             -- on dry land a hit counts 1.5x
					if not e._at_sea and (e._immersion_depth or 0) < 1 and target then
						r.hit_land = e.health
						hit(100)
						r.hit_land = r.hit_land - e.health
						-- and down to 20 %: he dives away
						e.health = 0.2 * HP
						go("E")
					elseif dt > 40 then go("E") end
				elseif phase == "E" then
					if dt == 1 then r.fleeing, r.flee_target = e._fleeing == true, target end
					if e._fleeing and not e:valid_enemy() and not r.dived then
						r.dived, r.flee_hp0 = dt, e.health
					end
					-- rate from the first healed sample: regen waits 5 s after the last hit, which may end mid-dive
					if r.dived and not r.flee_t0 and e.health > r.flee_hp0 then r.flee_hp0, r.flee_t0 = e.health, t end
					if r.flee_t0 and t > r.flee_t0 and flat(p, HOME) < 5 and e._current_animation == "dormant" and not r.flee_home then
						r.flee_home = dt
						r.flee_regen = (e.health - r.flee_hp0) / (t - r.flee_t0)
						e.health = 0.69 * HP -- (125 s of regeneration skipped)
						player:set_pos(SHORE)
						go("F")
					elseif dt > 50 then go("END") end
				elseif phase == "F" then             -- at 70 % he comes back for the intruder
					if not e._fleeing and not r.back then r.back, r.back_hp = dt, e.health end
					if r.back and target then
						r.back_target = dt
						-- hurt again, and this time the flight has lasted nearly FLEE_TIMEOUT (180 s)
						e.health = 0.2 * HP
						go("G")
					end
					if dt > 20 then go("END") end
				elseif phase == "G" then             -- the flee timeout: he comes back at 20 % and stays
					if dt == 1 then r.fled_again = e._fleeing == true; e._flee_time = 179 end
					if dt > 1 and not e._fleeing and not r.timeout_back then r.timeout_back, r.timeout_hp = dt - 1, e.health end
					if r.timeout_back and target then r.timeout_target = true end
					if dt >= 8 then r.cornered = e._fleeing ~= true and e._cornered == true; go("END") end
				end
				if phase == "END" or t >= 150 then
					T.result(r, {"asleep_y", "asleep_targetable", "head_out", "risen_targetable", "risen_sea", "hit_water", "regen_4s",
						"regen_15s", "hit_land", "fleeing", "flee_target", "dived", "flee_home", "flee_regen", "back", "back_hp", "back_target",
						"fled_again", "timeout_back", "timeout_hp", "timeout_target", "cornered", "sea_walk"}, {
						{"asleep_y", {-13.7, -13.3}}, {"asleep_targetable", false}, {"head_out", {3.5, 5.5}}, {"risen_targetable", true},
						{"risen_sea", true}, {"hit_water", {99.9, 100.1}}, {"regen_4s", {0, 0.1}}, {"regen_15s", {17, 23}},
						{"hit_land", {149.9, 150.1}}, {"fleeing", true}, {"flee_target", false}, {"dived", {1, 15}}, {"flee_home", "set"},
						{"flee_regen", {1.5, 2.2}}, {"back", "set"}, {"back_hp", {385, 400}}, {"back_target", "set"},
						{"fled_again", true}, {"timeout_back", {0, 2.5}}, {"timeout_hp", {100, 140}}, {"timeout_target", true}, {"cornered", true}, {"sea_walk", {0, 0}}})
					core.request_shutdown("done")
					return
				end
				core.after(0.5, tick)
			end
			core.after(0.5, tick)
		end)
	end)
end)
