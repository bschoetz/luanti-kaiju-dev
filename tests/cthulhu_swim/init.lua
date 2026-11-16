-- Cthulhu against a Gojira who swims in the middle of his sea. He must fight with head
-- and shoulders out of the water (Gojira's head is above it, though his feet are deep
-- below), so that Gojira can target him and fight back; and he is a valid enemy whenever
-- he attacks. Then he is hurt badly and dives away right next to Gojira: Gojira loses him
-- within a second (because he is under water, not because of distance or lost sight) and
-- does not find him again. Ends with a VALUES and a RESULT line (see tests/README.md). The
-- player only watches (creative).
local T = kaiju_test
local L, flat, name_of = T.log, T.flat, T.name_of
local HOME, SURFACE = T.SEA_HOME, T.SEA_SURFACE

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	T.sea(function()
		local list = {}
		for x = -37, -35 do for z = 9, 11 do for y = 9, 22 do list[#list + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(list, {name = "mcl_core:cobble"})
		player:set_pos({x = -36, y = 23, z = 10}); player:set_look_horizontal(-0.85); player:set_look_vertical(0.35)
		core.after(3, function()
			local c = core.add_entity(vector.offset(HOME, 0, 0.1, 0), "cthulhu:cthulhu")
			local g = core.add_entity(vector.new(12, 0, 36), "gojira:gojira")
			local t, phase, mark = 0, "fight", 0
			local r = {samples = 0, targetable = 0, head_out = 0, lost = true}
			local function go(name) phase, mark = name, t; L("PHASE " .. name) end
			local function tick()
				local e, o = c:get_luaentity(), g:get_luaentity()
				if not e or not o then L("RESULT FAIL: a kaiju is gone in phase " .. phase); core.request_shutdown("done"); return end
				t = t + 0.5
				local dt = t - mark
				local p, q = c:get_pos(), g:get_pos()
				local dist, attacks = flat(p, q), o.attack == c
				if t % 1 == 0 then
					L(("t=%d %s dist=%.1f | CTHULHU y=%.1f top_above_surface=%.1f hp=%d target=%s anim=%s valid_enemy=%s fleeing=%s | GOJIRA y=%.1f depth=%.1f hp=%d target=%s anim=%s"):format(
						t, phase, dist, p.y, p.y + 13 - SURFACE, e.health, name_of(e.attack), tostring(e._current_animation), tostring(e:valid_enemy()),
						tostring(e._fleeing == true), q.y, o._immersion_depth or 0, o.health, name_of(o.attack), tostring(o._current_animation)))
				end
				if phase == "fight" then
					if e.attack == g then
						r.cthulhu_attacks = r.cthulhu_attacks or dt
						if e:valid_enemy() then r.targetable = r.targetable + 1 end
						-- (the first seconds he is still on his way up from the sea floor)
						if dt >= r.cthulhu_attacks + 8 then
							r.samples = r.samples + 1
							if p.y + 13 > SURFACE + 2 then r.head_out = r.head_out + 1 end
						end
						r.attack_samples = (r.attack_samples or 0) + 1
					end
					if attacks and not r.gojira_fights_back then r.gojira_fights_back = dt end
					if dt >= 30 then
						r.gojira_depth = SURFACE - q.y -- (his _immersion_depth reads 0 at times in the release)
						r.cthulhu_hp, r.gojira_hp = e.health, o.health
						r.head_out_share = r.samples > 0 and r.head_out / r.samples or nil
						r.targetable_share = r.attack_samples and r.targetable / r.attack_samples or nil
						e.health = math.min(e.health, 100) -- below 25 %: he dives away
						go("dive")
					end
				elseif phase == "dive" then
					if not e:valid_enemy() and not r.submerged then r.submerged, r.submerged_dist = dt, dist end
					if not r.submerged then r.attacked_until_submerged = attacks end
					if r.submerged and not attacks then
						r.lets_go_delay = dt - r.submerged
						go("lost")
					end
					if dt >= 30 then go("END") end
				elseif phase == "lost" then          -- he rests under water, Gojira swims above him
					if not e:valid_enemy() and attacks then r.lost = false end
					r.lost_max_dist = math.max(r.lost_max_dist or 0, dist)
					if dt >= 6 then go("END") end
				end
				if phase == "END" then
					T.result(r, {"cthulhu_attacks", "gojira_fights_back", "gojira_depth", "head_out_share", "targetable_share", "cthulhu_hp",
						"gojira_hp", "attacked_until_submerged", "submerged", "submerged_dist", "lets_go_delay", "lost", "lost_max_dist"}, {
						{"cthulhu_attacks", {0, 2}}, {"gojira_fights_back", {0, 12}}, {"gojira_depth", {8, 30}}, {"head_out_share", {0.9, 1}},
						{"targetable_share", {1, 1}}, {"cthulhu_hp", {1, 549}}, {"gojira_hp", {1, 499}}, {"attacked_until_submerged", true},
						{"submerged", {0, 20}}, {"submerged_dist", {0, 31}}, {"lets_go_delay", {0, 1}}, {"lost", true}, {"lost_max_dist", {0, 31}}})
					core.request_shutdown("done")
					return
				end
				core.after(0.5, tick)
			end
			core.after(0.5, tick)
		end)
	end)
end)
