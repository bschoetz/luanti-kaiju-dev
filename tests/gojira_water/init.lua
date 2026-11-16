local function L(s) core.log("action", "[test] " .. s) end
local function fill(p1, p2, name)
	local list = {}
	for x = p1.x, p2.x do for y = p1.y, p2.y do for z = p1.z, p2.z do list[#list + 1] = vector.new(x, y, z) end end end
	core.bulk_set_node(list, {name = name})
end
local function region(z)
	if z >= 2 and z <= 12 then return "SHALLOW(4)" elseif z >= 16 and z <= 32 then return "DEEP(22)" else return "land" end
end
core.register_globalstep(function()
	for _, pl in ipairs(core.get_connected_players()) do if pl:get_hp() > 0 then pl:set_hp(20) end end
end)
core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function()
		fill(vector.new(-1, 9, -11), vector.new(1, 19, -9), "mcl_core:cobble")
		player:set_pos({x = 0, y = 20, z = -10})
		player:set_look_horizontal(0); player:set_look_vertical(0.35)
		core.after(2, function()
		local g = core.add_entity({x = 0, y = 8.6, z = 35}, "gojira:gojira")
		L("spawned " .. tostring(g and g:get_luaentity() ~= nil)); g:get_luaentity().view_range = 80
		local function wait()
			local e = g:get_luaentity()
			if e and e.attack then
				fill(vector.new(-20, 5, 2), vector.new(20, 8, 12), "mcl_core:water_source")
				fill(vector.new(-20, -13, 16), vector.new(20, 8, 32), "mcl_core:water_source")
				L("pools built, target locked")
				local last = g:get_pos()
				for i = 1, 60 do
					core.after(i * 0.5, function()
						local p = g:get_pos(); if not p then return end
						local ent = g:get_luaentity()
						L(("t=%.1f z=%.1f y=%.1f speed=%.2f n/s %s immersion=%.1f anim=%s breath=%s bulldoze=%s"):format(i * 0.5, p.z, p.y,
							vector.distance(vector.new(p.x, 0, p.z), vector.new(last.x, 0, last.z)) / 0.5, region(p.z),
							ent._immersion_depth or 0, tostring(ent._current_animation), tostring(ent._breath_time ~= nil), tostring(ent._bulldoze_time ~= nil)))
						last = p
					end)
				end
			else core.after(0.3, wait) end
		end
		wait()
		end)
	end)
	core.after(38, function() core.request_shutdown("done") end)
end)
