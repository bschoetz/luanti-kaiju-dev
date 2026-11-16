local function puppet(pos, yaw, anim, fps)
	local o = core.add_entity(pos, "mothra:mothra")
	o:get_luaentity().on_step = function(self) self.object:set_velocity(vector.zero()); self.object:set_yaw(yaw) end
	o:set_animation(anim, fps, 0, true)
	return o
end
core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function()
		local list = {}
		for x = -1, 1 do for z = -1, 1 do for y = 9, 22 do list[#list + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(list, {name = "mcl_core:cobble"})
		player:set_pos({x = 0, y = 23, z = 0}); player:set_look_horizontal(0); player:set_look_vertical(0.25)
		core.after(1, function()
			local p = puppet({x = 0, y = 17, z = 24}, math.pi * 0.85, {x = 50, y = 80}, 24)
			core.after(8, function() p:set_animation({x = 0, y = 40}, 20, 0, true) end)
			core.after(13, function() p:set_animation({x = 90, y = 120}, 12, 0, true) end)
			core.after(18, function() p:set_animation({x = 130, y = 170}, 20, 0, true) end)
		end)
	end)
	core.after(26, function() core.request_shutdown("done") end)
end)
