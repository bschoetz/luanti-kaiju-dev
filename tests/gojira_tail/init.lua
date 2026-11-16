local function L(s) core.log("action", "[test] " .. s) end
local function count(x1, z1, x2, z2)
	local _, c = core.find_nodes_in_area(vector.new(x1, 9, z1), vector.new(x2, 16, z2), "mcl_core:cobble")
	return c["mcl_core:cobble"] or 0
end
core.register_globalstep(function()
	for _, pl in ipairs(core.get_connected_players()) do if pl:get_hp() > 0 then pl:set_hp(20) end end
end)
core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function()
		player:set_pos({x = 0, y = 9, z = -34}); player:set_look_horizontal(0); player:set_look_vertical(-0.1)
		core.after(2, function()
			-- pillars every 2 nodes, 6 high, in front of and beside him (radius 4..22)
			local list = {}
			for x = -22, 22, 2 do for z = -4, 22, 2 do
				local d = math.sqrt(x * x + z * z)
				if d >= 4 and d <= 22 then for y = 9, 14 do list[#list + 1] = vector.new(x, y, z) end end
			end end
			core.bulk_set_node(list, {name = "mcl_core:cobble"})
			local g = core.add_entity({x = 0, y = 8.6, z = 0}, "gojira:gojira")
			local e = g:get_luaentity(); e:set_yaw(0); g:set_yaw(0)
			L(("before: front(z7..22)=%d  sides(|x|>=6,z-4..6)=%d"):format(count(-22, 7, 22, 22), count(-22, -4, -6, 6) + count(6, -4, 22, 6)))
			for t = 1, 12 do
				core.after(t, function()
					local p, en = g:get_pos(), g:get_luaentity()
					if not p then return end
					L(("t=%d yaw=%.0f pos=%s target=%s front(z7..22)=%d sides=%d"):format(t, math.deg(g:get_yaw()) % 360,
						core.pos_to_string(vector.round(p)), tostring(en.attack and en.attack:is_player() and "player" or en.attack),
						count(-22, 7, 22, 22), count(-22, -4, -6, 6) + count(6, -4, 22, 6)))
				end)
			end
		end)
	end)
	core.after(20, function() core.request_shutdown("done") end)
end)

-- timing: smash cost = gojira.ai_step minus the stock mob_class.ai_step inside it
core.register_on_mods_loaded(function()
	local def, mc = core.registered_entities["gojira:gojira"], kaiju_core.mcl_mobs.mob_class
	local inner, base, own = 0, mc.ai_step, def.ai_step
	mc.ai_step = function(...) local t = core.get_us_time(); base(...); inner = inner + (core.get_us_time() - t) / 1e6 end
	local max, sum, n = 0, 0, 0
	def.ai_step = function(...)
		inner = 0
		local t = core.get_us_time(); own(...); local d = (core.get_us_time() - t) / 1e6 - inner
		if d > 0.00005 then max = math.max(max, d); sum = sum + d; n = n + 1 end
		if d > 0.015 then
			local _, c = core.find_nodes_in_area(vector.new(-22, 9, -22), vector.new(22, 16, 22), "mcl_core:cobble")
			L(("SLOW tick %.1fms t=%.2f cobble_left=%d"):format(d * 1000, core.get_us_time() / 1e6, c["mcl_core:cobble"] or 0))
		end
	end
	core.after(19, function() L(("smash timing: ticks=%d max=%.2fms avg=%.2fms"):format(n, max * 1000, sum / math.max(n, 1) * 1000)) end)
end)
