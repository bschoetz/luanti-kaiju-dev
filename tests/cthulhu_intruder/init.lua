-- Who wakes Cthulhu and who doesn't, and how he gives up on a target he can't reach.
--   flyers:  a bat 2 nodes above the sea (a flyer by name) and an iron golem held 8 nodes
--            above it (anything with that much air under its feet is one) don't wake him;
--            the golem dropped into the water does (control).
--   cave:    a zombie in a sealed cell under ground, 9 nodes beyond the sea wall, doesn't
--            (and he breaks no blocks meanwhile); with a shaft to the sky above it, it
--            does (control).
--   tower:   the player on a pillar in the sea, 30 nodes above him. He swims there, can't
--            reach, and gives up after 12 s without having set foot on land; back home he
--            ignores the player for a while.
-- Ends with a VALUES and a RESULT line (see tests/README.md).
local T = kaiju_test
local L, flat, name_of = T.log, T.flat, T.name_of
local HOME = T.SEA_HOME
local OUTSIDE, TOWER = vector.new(0, 9.5, -16), vector.new(0, 0, 20)
local CELL = vector.new(-31, -5, 36)

T.keep_players_alive()
local removed = T.count_removed(p)

-- Holds a mob in place: no AI, no physics.
local function pin(obj)
	obj:get_luaentity().on_step = function() end
	obj:set_velocity(vector.zero()); obj:set_acceleration(vector.zero())
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	T.sea(function()
		player:set_pos(OUTSIDE); player:set_look_horizontal(0)
		-- the cell: 3x3x3 of air in a 7x7x7 block of stone
		local stone, air = {}, {}
		for x = -3, 3 do for y = -3, 3 do for z = -3, 3 do
			local inside = math.max(math.abs(x), math.abs(y), math.abs(z)) <= 1
			table.insert(inside and air or stone, vector.offset(CELL, x, y, z))
		end end end
		core.bulk_set_node(stone, {name = "mcl_core:stone"})
		core.bulk_set_node(air, {name = "air"})
		-- the tower: a pillar from the sea floor to y = 40
		local list = {}
		for y = -13, 40 do list[#list + 1] = vector.new(TOWER.x, y, TOWER.z) end
		core.bulk_set_node(list, {name = "mcl_core:cobble"})
		core.after(3, function()
			local c = core.add_entity(vector.offset(HOME, 0, 0.1, 0), "cthulhu:cthulhu")
			local bat = core.add_entity(vector.new(0, 10.5, 30), "mobs_mc:bat")
			local golem = core.add_entity(vector.new(6, 16.5, 30), "mobs_mc:iron_golem")
			pin(bat); pin(golem)
			local zombie
			local t, phase, mark, r = 0, "flyers", 0, {}
			local next_phase
			local function go(name) phase, mark = name, t; L("PHASE " .. name) end
			-- wait until he sleeps at home again, then go on
			local function settle(name) next_phase = name; go("settle") end
			local function tick()
				local e = c:get_luaentity()
				if not e then L("RESULT FAIL: cthulhu is gone"); core.request_shutdown("done"); return end
				t = t + 0.5
				local dt, p = t - mark, c:get_pos()
				local target = e.attack ~= nil
				local asleep = not target and e._current_animation == "dormant" and flat(p, HOME) < 6
				if t % 1 == 0 then
					L(("t=%d %s pos=%.1f,%.1f,%.1f sea=%s depth=%.1f target=%s anim=%s land_time=%.1f stall=%.1f returning=%s ignored=%s removed=%d"):format(
						t, phase, p.x, p.y, p.z, tostring(e._at_sea == true), e._immersion_depth or 0, name_of(e.attack), tostring(e._current_animation),
						e._land_time or 0, e._stall_time or 0, tostring(e._returning == true), name_of(e._ignored), removed(p)))
				end
				if phase == "flyers" then
					if dt >= 3 then r.flyers_ignored = (r.flyers_ignored ~= false) and asleep end -- (3 s to settle after the spawn)
					if dt >= 10 then
						r.bat_alive = bat:is_valid()
						-- control: the same golem in the water
						golem:set_pos(vector.new(6, 8, 30))
						go("golem_swims")
					end
				elseif phase == "golem_swims" then
					if e.attack == golem or dt >= 8 then
						r.golem_in_water_woke = e.attack == golem and dt
						golem:remove(); bat:remove()
						settle("cave")
					end
				elseif phase == "settle" then
					if asleep or dt >= 40 then
						r["settled_before_" .. next_phase] = asleep
						if next_phase == "cave" then
							zombie = core.add_entity(vector.offset(CELL, 0, -1.4, 0), "mobs_mc:zombie")
							zombie:get_luaentity().persistent = true
							removed(true)
						elseif next_phase == "tower" then
							player:set_pos(vector.new(TOWER.x, 41.5, TOWER.z))
						end
						go(next_phase)
					end
				elseif phase == "cave" then
					r.cave_ignored = (r.cave_ignored ~= false) and asleep
					if dt >= 10 then
						r.cave_removed = removed(p)
						r.zombie_alive = zombie:is_valid()
						-- control: a shaft from the cell to the sky
						local shaft = {}
						for y = CELL.y + 2, 9 do shaft[#shaft + 1] = vector.new(CELL.x, y, CELL.z) end
						core.bulk_set_node(shaft, {name = "air"})
						go("shaft")
					end
				elseif phase == "shaft" then
					if e.attack == zombie or dt >= 8 then
						r.shaft_woke = e.attack == zombie and dt
						if zombie:is_valid() then zombie:remove() end
						settle("tower")
					end
				elseif phase == "tower" then
					if target and not r.tower_woke then r.tower_woke = dt end
					r.tower_land_time = math.max(r.tower_land_time or 0, e._land_time or 0)
					if e._returning then
						r.gave_up = dt - (r.tower_woke or 0)
						r.gave_up_dist = flat(p, TOWER)
						go("ignored")
					elseif dt >= 60 then go("END") end
				elseif phase == "ignored" then       -- the player stays where he is
					if asleep and not r.home_again then r.home_again = dt end
					if r.home_again then
						r.stays_asleep = (r.stays_asleep ~= false) and asleep
						if dt >= r.home_again + 12 then go("END") end
					elseif dt >= 40 then go("END") end
				end
				if phase == "END" then
					T.result(r, {"flyers_ignored", "bat_alive", "golem_in_water_woke", "settled_before_cave", "cave_ignored", "cave_removed",
						"zombie_alive", "shaft_woke", "settled_before_tower", "tower_woke", "tower_land_time", "gave_up", "gave_up_dist",
						"home_again", "stays_asleep"}, {
						{"flyers_ignored", true}, {"bat_alive", true}, {"golem_in_water_woke", {0, 4}}, {"settled_before_cave", true},
						{"cave_ignored", true}, {"cave_removed", {0, 0}}, {"zombie_alive", true}, {"shaft_woke", {0, 3}},
						{"settled_before_tower", true}, {"tower_woke", {0, 2}}, {"tower_land_time", {0, 0.5}}, {"gave_up", {12, 24}},
						{"gave_up_dist", {0, 12}}, {"home_again", {1, 30}}, {"stays_asleep", true}})
					core.request_shutdown("done")
					return
				end
				core.after(0.5, tick)
			end
			core.after(0.5, tick)
		end)
	end)
end)
