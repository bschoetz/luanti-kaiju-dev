-- Cthulhu's tentacle grab: he pulls the driver out of a boat (the boat stays), drags the
-- victim under water in front of his mouth and lets go after 6 s; the same with a small mob
-- (an iron golem); he lets go at once when the victim dies, when he takes 25 damage and
-- when he dies. No grip entity is left behind, and the victim is never held inside the
-- shore. Also logs the madness aura (nausea, darkness up close) on the player. Ends with a
-- VALUES and a RESULT line (see tests/README.md).
local T = kaiju_test
local L, flat, name_of = T.log, T.flat, T.name_of
local HOME = T.SEA_HOME
-- BEYOND is outside his leash; the three shore spots are on different sides of the sea
-- (he digs into the shore where he comes out)
local BEYOND, BOAT = vector.new(0, 9.5, -40), vector.new(0, 9, 22)
local EAST, WEST, NORTH = vector.new(25, 9.5, 36), vector.new(-25, 9.5, 36), vector.new(0, 9.5, 61)
local SOUTH = vector.new(6, 9.5, 12)

local squeezed = 0
core.register_on_player_hpchange(function(player, change)
	if player:get_attach() and change < 0 then squeezed = squeezed - change end
end)
T.keep_players_alive()

local function grips()
	local n = 0
	for _, ent in pairs(core.luaentities) do if ent.name == "cthulhu:grip" then n = n + 1 end end
	return n
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	T.sea(function()
		player:set_pos(BEYOND); player:set_look_horizontal(0)
		core.after(3, function()
			local c = core.add_entity(vector.offset(HOME, 0, 0.1, 0), "cthulhu:cthulhu")
			local e = c:get_luaentity()
			local boat = core.add_entity(BOAT, "mcl_boats:boat")
			player:set_pos(BOAT)
			local golem
			local t, phase, mark, r = 0, "boat", 0, {}
			local held, min_y -- per grab: since when, lowest point
			local buried = 0  -- consecutive samples (0.25 s) of a held victim inside a solid node
			r.buried = 0      -- the longest such run of all grabs
			local function go(name) phase, mark, held, min_y = name, t, nil, nil; L("PHASE " .. name) end
			local function victim() return (phase == "golem" or phase == "victim_death") and golem or player end
			local function solid(p)
				local def = core.registered_nodes[core.get_node(p).name]
				return not def or def.walkable
			end
			-- "held" and "freed" of the current victim; returns the hold time once it is released
			local function watch()
				local v = victim()
				if not v:is_valid() then return held and t - held end -- (a dead victim's body is gone)
				local parent = v:get_attach()
				local on_grip = parent and parent:get_luaentity() and parent:get_luaentity().name == "cthulhu:grip"
				if on_grip then
					held = held or t
					local vp = v:get_pos()
					min_y = math.min(min_y or 99, vp.y)
					-- (the grip passes through nodes on its way; staying inside one is the bug)
					buried = (solid(vp) or solid(vector.offset(vp, 0, 1.5, 0))) and buried + 1 or 0
					r.buried = math.max(r.buried, buried)
				elseif held then
					return t - held
				end
			end
			core.after(1, function()
				boat:get_luaentity():on_rightclick(player)
				L("in boat: " .. tostring(player:get_attach() == boat))
			end)
			local function tick()
				e = c:get_luaentity()
				if not e then L("RESULT FAIL: cthulhu is gone"); core.request_shutdown("done"); return end
				t = t + 0.25
				local p, dt = c:get_pos(), t - mark
				local hold = watch()
				if t % 1 == 0 then
					local vp = victim():get_pos() or vector.zero()
					L(("t=%d %s cthulhu=%.0f,%.1f,%.0f anim=%s target=%s grab_t=%s victim=%.1f,%.1f,%.1f attached=%s in=%s grips=%d nausea=%s darkness=%s squeezed=%d hp=%d"):format(
						t, phase, p.x, p.y, p.z, tostring(e._current_animation), tostring(e.attack ~= nil), tostring(e._grab_t and math.floor(e._grab_t * 10) / 10),
						vp.x, vp.y, vp.z, tostring(victim():is_valid() and victim():get_attach() ~= nil), core.get_node(vp).name, grips(),
						tostring(mcl_potions.has_effect(player, "nausea")), tostring(mcl_potions.has_effect(player, "darkness")), squeezed, e.health))
				end
				if e.attack then
					r.nausea = r.nausea or mcl_potions.has_effect(player, "nausea")
					r.darkness = r.darkness or mcl_potions.has_effect(player, "darkness")
				end
				if phase == "boat" then
					if held and not r.boat_pulled then
						r.boat_pulled, r.boat_stays, r.boat_driver = true, boat:is_valid(), tostring(boat:get_luaentity()._driver)
					end
					if hold then
						r.boat_hold, r.boat_min_y, r.boat_released_in, r.boat_squeezed = hold, min_y, core.get_node(player:get_pos()).name, squeezed
						r.boat_grips = grips()
						player:set_pos(BEYOND)
						golem = core.add_entity(EAST, "mobs_mc:iron_golem")
						e._grab_cooldown = 0
						go("golem")
					end
				elseif phase == "golem" then
					if hold then
						r.golem_hold, r.golem_min_y, r.golem_damage = hold, min_y, 550 - e.health
						golem:remove()
						golem = core.add_entity(SOUTH, "mobs_mc:iron_golem")
						e._grab_cooldown = 0
						go("victim_death")
					end
				elseif phase == "victim_death" then  -- the victim dies in his claws
					if held and not r.victim_killed and t - held >= 1 then
						r.victim_killed = t
						mcl_util.deal_damage(golem, 1000, {type = "generic"})
					end
					if hold and r.victim_killed then
						r.victim_death_release = t - r.victim_killed
						if golem:is_valid() then golem:remove() end
						e._grab_cooldown = 0
						player:set_pos(WEST)
						go("struggle")
					end
				elseif phase == "struggle" then      -- 30 damage while he holds the player
					if dt == 0.5 then r.victim_death_grab_over = e._grab_t == nil end
					if held and not r.struggle_hit and t - held >= 1 then
						r.struggle_hit = t
						mcl_util.deal_damage(c, 30, {type = "mob", source = player, direct = player})
					end
					if hold and r.struggle_hit then
						r.struggle_release = t - r.struggle_hit
						e._grab_cooldown = 0
						player:set_pos(NORTH)
						go("death")
					end
				elseif phase == "death" then         -- he dies while he holds the player
					if held and not r.death_hit and t - held >= 1 then
						r.death_hit = t
						e.health = 1
						mcl_util.deal_damage(c, 50, {type = "mob", source = player, direct = player})
					end
					if hold and r.death_hit then
						r.death_release, r.death_grips, r.dead = t - r.death_hit, grips(), e.dead == true
						go("END")
					end
				end
				if dt > 45 then L("timeout in phase " .. phase); go("END") end
				if phase == "END" then
					core.after(1, function()
						r.grips_left = grips()
						T.result(r, {"boat_pulled", "boat_stays", "boat_driver", "boat_hold", "boat_min_y", "boat_released_in", "boat_squeezed",
							"boat_grips", "golem_hold", "golem_min_y", "golem_damage", "victim_death_release", "victim_death_grab_over",
							"struggle_release", "death_release", "death_grips", "dead", "nausea", "darkness", "buried", "grips_left"}, {
							{"boat_pulled", true}, {"boat_stays", true}, {"boat_driver", "nil"}, {"boat_hold", {5, 6.5}}, {"boat_min_y", {-13, 6.6}},
							{"boat_released_in", "mcl_core:water_source"}, {"boat_squeezed", {8, 12}}, {"golem_hold", {5, 6.5}},
							{"golem_min_y", {-13, 6.6}}, {"victim_death_release", {0, 0.5}}, {"victim_death_grab_over", true},
							{"struggle_release", {0, 0.5}}, {"death_release", {0, 0.5}}, {"dead", true}, {"nausea", true}, {"darkness", true},
							{"buried", {0, 4}}, {"grips_left", {0, 0}}})
						core.request_shutdown("done")
					end)
					return
				end
				core.after(0.25, tick)
			end
			core.after(0.25, tick)
		end)
	end)
end)
