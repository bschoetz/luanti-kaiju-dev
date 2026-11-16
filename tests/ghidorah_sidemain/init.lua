-- Ghidorah's side heads in a one-on-one melee. Gojira and Ghidorah fight for 40 s (both
-- kept alive, the player 55 nodes away): while he has Gojira in melee the side heads fire
-- volleys at him (`_beam_side == "main"`), which hurt him, and he doesn't bite meanwhile.
-- Then Gojira is removed and the survival player pinned 5 nodes in front of Ghidorah for
-- 14 s: the side heads can't turn that far down, their beams would miss, so no volley.
-- Good: "RESULT ok".
local T = kaiju_test
T.keep_players_alive()
core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(4, function()
		player:set_pos(vector.new(0, 9, -40))
		local g = core.add_entity(vector.new(-10, 8.6, 15), "gojira:gojira")
		local k = core.add_entity(vector.new(10, 8.6, 15), "ghidorah:ghidorah")
		local ke = k:get_luaentity()
		local r = {main_volleys = 0, main_damage = 0, player_volleys = 0}
		local t, main, pin, done = 0, false, nil, false
		core.register_globalstep(function(dtime)
			if done or not k:is_valid() then return end
			t = t + dtime
			local now = ke._beam_time ~= nil and ke._beam_side == "main"
			local ge = g:is_valid() and g:get_luaentity()
			if ge then
				if now then r.main_damage = r.main_damage + 500 - ge.health end
				ge.health = 500
			end
			ke.health, ke._head_hp = 600, {c = 120, l = 120, r = 120}
			if now and not main then
				if pin then r.player_volleys = r.player_volleys + 1 else r.main_volleys = r.main_volleys + 1 end
			end
			main = now
			if pin then player:set_pos(pin) end
			if t >= 40 and not pin then
				g:remove()
				ke._side_main_cd = 0
				pin = vector.add(vector.new(k:get_pos().x, 8.5, k:get_pos().z), vector.multiply(core.yaw_to_dir(k:get_yaw()), 5))
			elseif t >= 54 then
				done = true
				r.target = T.name_of(ke.attack)
				T.result(r, {"main_volleys", "main_damage", "player_volleys", "target"},
					{{"main_volleys", {2, 5}}, {"main_damage", {1, 500}}, {"player_volleys", {0, 0}}, {"target", "player"}})
				core.request_shutdown("done")
			end
		end)
	end)
end)
