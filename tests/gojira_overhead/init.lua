-- A target above Gojira's feet but below his head (a swimmer over deep water, a player on a
-- roof): the melee standoff is measured horizontally, the bite in 3D. The player hovers
-- 5.8 nodes above his feet; stopping at the standoff gap (4.7) would leave him 7.5 away,
-- out of his reach (7), so he must close in further and bite. Fire breath is off.
-- Good: the last line is "RESULT ok".
local function L(s) core.log("action", "[test] " .. s) end
local SPOT = vector.new(0, 14.3, -10) -- feet 5.8 above his (8.5)

core.register_globalstep(function()
	for _, pl in ipairs(core.get_connected_players()) do
		if pl:get_hp() > 0 then pl:set_hp(20) end
		-- bites knock the hovering player away
		if pl:get_physics_override().gravity == 0 and vector.distance(pl:get_pos(), SPOT) > 0.5 then pl:set_pos(SPOT) end
	end
end)

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function()
		player:set_physics_override({gravity = 0})
		player:set_pos(SPOT)
		core.after(2, function()
			local g = core.add_entity({x = 0, y = 8.6, z = 20}, "gojira:gojira")
			local e = g:get_luaentity()
			e._breath_cooldown = 1e9
			local bites, bite = 0, e.custom_attack
			e.custom_attack = function(...) bites = bites + 1; return bite(...) end
			for t = 1, 14 do
				core.after(t, function()
					local p, tp = g:get_pos(), player:get_pos()
					L(("t=%d flat=%.1f dist=%.1f (reach %d) player %.1f above his feet | anim=%s target=%s bites=%d"):format(t,
						math.sqrt((p.x - tp.x) ^ 2 + (p.z - tp.z) ^ 2), vector.distance(p, tp), e.reach, tp.y - p.y,
						tostring(e._current_animation), tostring(e.attack ~= nil), bites))
				end)
			end
			core.after(14.5, function()
				L(bites > 0 and "RESULT ok" or "RESULT FAIL: he never bit the target above him")
			end)
		end)
	end)
	core.after(20, function() core.request_shutdown("done") end)
end)
