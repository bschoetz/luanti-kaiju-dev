-- The three modpack settings (kaiju/settingtypes.txt). test.conf starts with all of them
-- off (phase "off"); then they are switched on at runtime, which is their default (phase
-- "on"). Each phase: Gojira behind a cobble wall he must break to reach the player, one
-- flame shot at a wooden wall, and a beam volley of Ghidorah at the player, who is made
-- unpointable so that the beams pass through him into the ground.
-- Good: RESULT ok: "off" changes nothing (wall_broken=0 fire=0 crater=0), "on" gives all
-- three > 0.
local function L(s) core.log("action", "[test] " .. s) end
local SETTINGS = {"kaiju_smash_blocks", "kaiju_gojira_fire", "kaiju_ghidorah_beam_blasts"}

local function fill(p1, p2, name)
	local list = {}
	for x = p1.x, p2.x do for y = p1.y, p2.y do for z = p1.z, p2.z do list[#list + 1] = vector.new(x, y, z) end end end
	core.bulk_set_node(list, {name = name})
end
local function count(name, p1, p2)
	local _, c = core.find_nodes_in_area(p1, p2, name); return c[name] or 0
end
local WALL1, WALL2 = vector.new(-5, 9, 14), vector.new(5, 15, 15)
local WOOD1, WOOD2 = vector.new(30, 9, -3), vector.new(31, 14, 3)
local GROUND1, GROUND2 = vector.new(-15, 6, -40), vector.new(15, 8, 0)

core.register_globalstep(function()
	for _, pl in ipairs(core.get_connected_players()) do if pl:get_hp() > 0 then pl:set_hp(20) end end
end)

local r = {}

local function phase(tag, player, done)
	fill(WALL1, WALL2, "mcl_core:cobble")
	fill(WOOD1, WOOD2, "mcl_core:wood")
	local wall, ground = count("mcl_core:cobble", WALL1, WALL2), count("air", GROUND1, GROUND2)
	local g = core.add_entity({x = 0, y = 8.6, z = 21}, "gojira:gojira")
	g:get_luaentity()._breath_cooldown = 1e9 -- no breath of his own: one flame is shot below
	core.after(1, function()
		-- like shoot_flame in gojira/init.lua
		local f = core.add_entity({x = 20, y = 11.5, z = 0}, "gojira:flame")
		local fe = f:get_luaentity()
		f:set_velocity(vector.new(fe.velocity, 0, 0))
		fe.switch, fe.owner_id, fe._shooter = 1, tostring(g), g
	end)
	local fire = 0
	core.after(2, function() fire = count("mcl_fire:fire", vector.new(25, 8, -5), vector.new(32, 16, 5)) end)
	core.after(5, function()
		local broken = wall - count("mcl_core:cobble", WALL1, WALL2)
		g:remove()
		local k = core.add_entity({x = 0, y = 8.6, z = 8}, "ghidorah:ghidorah")
		local beamed = false
		for i = 1, 20 do core.after(i * 0.25, function()
			local e = k:get_luaentity()
			beamed = beamed or (e and e._beam_fired) or false
		end) end
		core.after(5, function()
			k:remove()
			r[tag .. "_wall"], r[tag .. "_fire"], r[tag .. "_crater"] = broken, fire, count("air", GROUND1, GROUND2) - ground
			L(("%s: smash=%s fire=%s blasts=%s -> wall_broken=%d fire=%d beams_fired=%s crater=%d"):format(tag,
				core.settings:get("kaiju_smash_blocks"), core.settings:get("kaiju_gojira_fire"),
				core.settings:get("kaiju_ghidorah_beam_blasts"), broken, fire, tostring(beamed),
				count("air", GROUND1, GROUND2) - ground))
			done()
		end)
	end)
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	L("griefing=" .. tostring(kaiju_core.mob_griefing("gojira:gojira")))
	core.after(2, function()
		player:set_pos({x = 0, y = 9, z = -12}); player:set_look_horizontal(0)
		player:set_properties({pointable = false})
		core.after(2, function()
			phase("off", player, function()
				for _, s in ipairs(SETTINGS) do core.settings:set_bool(s, true) end
				phase("on", player, function()
					kaiju_test.result(r, {"off_wall", "off_fire", "off_crater", "on_wall", "on_fire", "on_crater"},
						{{"off_wall", 0}, {"off_fire", 0}, {"off_crater", 0},
						{"on_wall", {1, 1000}}, {"on_fire", {1, 1000}}, {"on_crater", {1, 1000}}})
					core.request_shutdown("done")
				end)
			end)
		end)
	end)
	core.after(60, function() core.request_shutdown("timeout") end)
end)
