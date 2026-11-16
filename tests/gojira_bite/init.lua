-- Gojira stands through his bite: he used to walk on while the bite clip played (about 6
-- nodes per bite of a player he was chasing: sliding feet). A survival player 30 nodes
-- away is chased and bitten (each bite throws the player, so he keeps arriving) for 25 s,
-- breath off. Logged: the bites and the distance he moved while the "punch" clip played.
-- Good: "RESULT ok".
local T = kaiju_test
T.keep_players_alive()
core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(4, function()
		player:set_pos(vector.new(0, 9, -10))
		local g = core.add_entity(vector.new(0, 8.6, 20), "gojira:gojira")
		local last, punching, t, done = g:get_pos(), false, 0, false
		local r = {bites = 0, glide = 0}
		core.register_globalstep(function(dtime)
			local e, p = g:get_luaentity(), g:get_pos()
			if done or not e then return end
			e._breath_cooldown = 99
			local punch = e._current_animation == "punch"
			if punch and not punching then r.bites = r.bites + 1 end
			if punch and punching then r.glide = r.glide + T.flat(p, last) end
			last, punching, t = p, punch, t + dtime
			if t >= 25 then
				done = true
				r.per_bite = r.glide / math.max(r.bites, 1)
				T.result(r, {"bites", "glide", "per_bite"}, {{"bites", {3, 30}}, {"per_bite", {0, 1.5}}})
				core.request_shutdown("done")
			end
		end)
	end)
end)
