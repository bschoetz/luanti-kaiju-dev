-- Cthulhu and the other kaiju. Part 1, on land, with a Cthulhu who is kept from picking
-- targets himself (so only the others' rules are measured): Gojira and Ghidorah ignore
-- him at about 50 nodes and attack within 32; Mothra ignores him while he is calm (her
-- gusts and powder at a husk between his feet don't hurt him), attacks while he is after
-- someone (an iron golem) and lets go when he calms down. Part 2, at sea: he ignores a
-- Gojira on a truce retreat in his territory, attacks him once the retreat is over, the
-- two fight at the shore, he lets go when Gojira is on a retreat again, and Gojira loses
-- him when he dives away. Ends with a VALUES and a RESULT line (see tests/README.md). The
-- player only watches (creative).
local T = kaiju_test
local L, flat, name_of = T.log, T.flat, T.name_of
local HOME = T.SEA_HOME
local LAND = vector.new(0, 8.6, -70)


core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	T.sea(function()
		-- the land arena: no trees between the kaiju
		local list = {}
		for x = -60, 60 do for z = -100, -40 do for y = 9, 24 do list[#list + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(list, {name = "air"})
		list = {}
		for x = -37, -35 do for z = 9, 11 do for y = 9, 22 do list[#list + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(list, {name = "mcl_core:cobble"})
		-- at the south-west corner of the sea, looking across it (part 1 is behind the player)
		player:set_pos({x = -36, y = 23, z = 10}); player:set_look_horizontal(-0.85); player:set_look_vertical(0.35)
		core.after(3, function()
			local c = core.add_entity(LAND, "cthulhu:cthulhu")
			local calm = function() return nil end
			c:get_luaentity().get_active_target = calm -- (shadows the class method on this one mob)
			local other, bait, husk                    -- the kaiju under test, the golem, Mothra's prey
			local HUSK = vector.offset(LAND, 4, 0, 0)  -- just outside his collision box
			local function retreat(o, on, x)          -- as kaiju_core.start_truce sets it
				o._retreat_x, o._retreat_z = on and (x or 30) or nil, on and 2 or nil
				o._retreat_until, o._retreat_attack_id = on and core.get_gametime() + 60 or nil, on and (o._last_attack_id or 0) or nil
			end
			local t, phase, mark, r = 0, "start", 0, {}
			local function go(name) phase, mark = name, t; L("PHASE " .. name) end
			local function spawn(name, pos) other = core.add_entity(pos, name) end
			local function tick()
				local e, o = c:get_luaentity(), other and other:get_luaentity()
				if not e or (other and not o) then L("RESULT FAIL: a kaiju is gone in phase " .. phase); core.request_shutdown("done"); return end
				t = t + 0.5
				local dt = t - mark
				local p, op = c:get_pos(), other and other:get_pos()
				local dist = op and flat(p, op) or 0
				if t % 1 == 0 then
					L(("t=%d %s dist=%.1f | CTHULHU y=%.1f hp=%d target=%s anim=%s sea=%s valid_enemy=%s fleeing=%s | %s hp=%d target=%s anim=%s retreat=%s"):format(
						t, phase, dist, p.y, e.health, name_of(e.attack), tostring(e._current_animation), tostring(e._at_sea == true),
						tostring(e:valid_enemy()), tostring(e._fleeing == true), o and name_of(other) or "-", o and o.health or 0,
						o and name_of(o.attack) or "-", o and tostring(o._current_animation) or "-", tostring(o and o._retreat_until ~= nil)))
				end
				local attacks = o and o.attack == c
				if phase == "start" then
					spawn("gojira:gojira", vector.offset(LAND, 50, 0, 0)); go("gojira_far")
				elseif phase == "gojira_far" or phase == "ghidorah_far" then
					local k = phase:gsub("_far", "")
					r[k .. "_far"] = (r[k .. "_far"] ~= false) and not attacks
					r[k .. "_far_min"] = math.min(r[k .. "_far_min"] or 99, dist)
					if dt >= 4 then other:set_pos(vector.offset(p, 28, 0, 0)); go(k .. "_near") end
				elseif phase == "gojira_near" or phase == "ghidorah_near" then
					local k = phase:gsub("_near", "")
					if attacks or dt >= 10 then
						r[k .. "_near"] = attacks and dt
						other:remove()
						if k == "gojira" then
							spawn("ghidorah:ghidorah", vector.offset(LAND, 50, 0, 0)); go("ghidorah_far")
						else
							spawn("mothra:mothra", vector.offset(LAND, 0, 18, 30)); go("mothra_calm")
						end
					end
				elseif phase == "mothra_calm" then
					r.mothra_calm = (r.mothra_calm ~= false) and not attacks
					if dt >= 6 then
						husk = core.add_entity(HUSK, "mobs_mc:husk")
						r.spares_husk_damage = 0
						go("mothra_spares")
					end
				elseif phase == "mothra_spares" then -- she fights a husk at his feet: he is not hurt
					local h = husk:get_luaentity()
					-- (her gusts throw it away and would kill it)
					husk:set_pos(HUSK); husk:set_velocity(vector.zero())
					if h then r.spares_husk_damage = r.spares_husk_damage + 20 - h.health; h.health = 20 end
					if o._current_animation == "punch" then r.spares_gust = true end
					if o._current_animation == "powder" then r.spares_powder = true end
					r.spares_cthulhu_hp = e.health
					if (r.spares_gust and r.spares_powder and r.spares_husk_damage >= 13) or dt >= 25 then
						husk:remove()
						bait = core.add_entity(vector.offset(LAND, -12, 0, 0), "mobs_mc:iron_golem")
						e.get_active_target = function() return bait end
						go("mothra_aggressive")
					end
				elseif phase == "mothra_aggressive" then
					if attacks and not r.mothra_aggressive then r.mothra_aggressive = dt end
					-- (the control for mothra_spares: now that he is her target, she does hurt him)
					if e._last_attacker == other or dt >= 20 then
						r.mothra_hurts_aggressive = e._last_attacker == other
						e.get_active_target = calm
						go("mothra_calm_again")
					end
				elseif phase == "mothra_calm_again" then
					if not attacks or dt >= 10 then
						r.mothra_lets_go = not attacks and dt
						other:remove(); bait:remove(); c:remove()
						-- part 2: a Cthulhu asleep at home, a retreating Gojira walks along the beach
						c = core.add_entity(vector.offset(HOME, 0, 0.1, 0), "cthulhu:cthulhu")
						spawn("gojira:gojira", vector.new(-30, 8.6, 2))
						retreat(other:get_luaentity(), true)
						go("truce")
					end
				elseif phase == "truce" then
					r.truce_ignored = (r.truce_ignored ~= false) and e.attack == nil
					r.truce_max_home_dist = math.max(r.truce_max_home_dist or 0, flat(op, HOME))
					if dt >= 6 then retreat(o, false); go("fight") end
				elseif phase == "fight" then
					if e.attack == other and not r.intruder then r.intruder = dt end
					if attacks and not r.gojira_fights_back then r.gojira_fights_back = dt end
					if dt >= 30 or e.health < 200 or o.health < 100 then
						r.fight_time, r.fight_cthulhu_hp, r.fight_gojira_hp = dt, e.health, o.health
						retreat(o, true, op.x > 0 and -45 or 45) -- (far enough not to arrive in this phase)
						go("truce_again")
					end
				elseif phase == "truce_again" then   -- a truce retreat also protects the kaiju he is fighting
					if e.attack == nil and not r.truce_lets_go then r.truce_lets_go = dt end
					if dt >= 1.5 then r.truce_kept = (r.truce_kept ~= false) and e.attack == nil and o._retreat_until ~= nil end
					if dt >= 5 then retreat(o, false); go("regain") end
				elseif phase == "regain" then        -- they fight again; then he is hurt badly
					-- (with his head out of the water again, so that the dive can be timed)
					local again = attacks and e.attack == other and p.y + 13 > T.SEA_SURFACE + 2
					if again or dt >= 20 then
						r.regain = again and dt
						e.health = math.min(e.health, 100) -- below 25 %: he dives away
						go("dive")
					end
				elseif phase == "dive" then
					-- Gojira must lose him because he is under water (valid_enemy), not because he
					-- is beyond the 32 nodes of Gojira's rule or out of sight for 3 s: so within a
					-- second of his head going under, and while he is still close
					if not e:valid_enemy() and not r.submerged then r.submerged, r.submerged_dist = dt, dist end
					if not r.submerged then r.attacked_until_submerged = attacks end
					if r.submerged and not attacks then
						r.gojira_lets_go, r.lets_go_delay = dt, dt - r.submerged
						go("END")
					end
					if dt >= 30 then go("END") end
				end
				if phase == "END" then
					T.result(r, {"gojira_far", "gojira_far_min", "gojira_near", "ghidorah_far", "ghidorah_far_min", "ghidorah_near",
						"mothra_calm", "spares_gust", "spares_powder", "spares_husk_damage", "spares_cthulhu_hp", "mothra_aggressive",
						"mothra_hurts_aggressive", "mothra_lets_go", "truce_ignored", "truce_max_home_dist", "intruder", "gojira_fights_back",
						"fight_time", "fight_cthulhu_hp", "fight_gojira_hp", "truce_lets_go", "truce_kept", "regain", "attacked_until_submerged",
						"submerged", "submerged_dist", "gojira_lets_go", "lets_go_delay"}, {
						{"gojira_far", true}, {"gojira_far_min", {40, 60}}, {"gojira_near", {0, 2}}, {"ghidorah_far", true},
						{"ghidorah_far_min", {40, 60}}, {"ghidorah_near", {0, 2}}, {"mothra_calm", true}, {"spares_gust", true},
						{"spares_powder", true}, {"spares_husk_damage", {13, 1000}}, {"spares_cthulhu_hp", {550, 550}},
						{"mothra_aggressive", {0, 2}}, {"mothra_hurts_aggressive", true}, {"mothra_lets_go", {0, 2}}, {"truce_ignored", true},
						{"truce_max_home_dist", {0, 48}}, {"intruder", {0, 2}}, {"gojira_fights_back", {0, 20}}, {"fight_cthulhu_hp", {1, 549}},
						{"fight_gojira_hp", {1, 499}}, {"truce_lets_go", {0, 1}}, {"truce_kept", true}, {"regain", {0, 20}},
						{"attacked_until_submerged", true}, {"submerged", {0, 20}}, {"submerged_dist", {0, 31}}, {"lets_go_delay", {0, 1}}})
					core.request_shutdown("done")
					return
				end
				core.after(0.5, tick)
			end
			core.after(0.5, tick)
		end)
	end)
end)
