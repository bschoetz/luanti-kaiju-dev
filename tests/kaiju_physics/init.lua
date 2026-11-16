-- A knocked-back kaiju flies as far on VoxeLibre as on Mineclonia: the layer's gravity is
-- Mineclonia's. A passive Ghidorah on flat ground gets Mothra's gust (22 nodes/s sideways,
-- 6 up); logged: the time in the air and how far he drifts within 2 s.
-- Good: "RESULT ok" (Mineclonia: about 0.4 s and 7 nodes; with VoxeLibre's own gravity,
-- 14.7, it was 0.8 s and 9 nodes, which kept Gojira out of melee twice as long).
local T = kaiju_test
core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(4, function()
		local k = core.add_entity(vector.new(0, 8.6, 20), "ghidorah:ghidorah")
		local e = k:get_luaentity()
		e.attack_type, e._targeting_rules, e.ai_functions = false, {}, {}
		core.after(2, function()
			local p0, t, air, r = k:get_pos(), 0, 0, {}
			k:add_velocity(vector.new(22, 6, 0))
			core.register_globalstep(function(dtime)
				if r.drift then return end
				local p = k:get_pos()
				t = t + dtime
				if p.y > p0.y + 0.05 then air = air + dtime end
				if t >= 2 then
					r.air, r.drift = air, p.x - p0.x
					T.result(r, {"air", "drift"}, {{"air", {0.25, 0.55}}, {"drift", {5, 8.5}}})
					core.request_shutdown("done")
				end
			end)
		end)
	end)
end)
