-- King Ghidorah behaviour: walking + beams at a player, a head severed and regrowing,
-- taking off for a flying Mothra, landing again, and dying when all three heads are off.
-- a full draw: Mineclonia takes a factor, VoxeLibre the speed (its bow's maximum)
local POWER = kaiju_core.voxelibre and 40 or 1.0
local function L(s) core.log("action", "[test] " .. s) end
local HEADS = {"c", "l", "r"}

core.register_globalstep(function()
	for _, pl in ipairs(core.get_connected_players()) do if pl:get_hp() > 0 then pl:set_hp(20) end end
end)

-- a hit on a head's hit box (ghidorah:hitbox, kept in _hitbox_<head>)
local function hit_at(g, h, dmg)
	mcl_util.deal_damage(g:get_luaentity()["_hitbox_" .. h], dmg, {type = "mob"})
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function()
		player:set_pos({x = 0, y = 9, z = -30}); player:set_look_horizontal(0); player:set_look_vertical(0.1)
		core.after(2, function()
			local g = core.add_entity({x = 0, y = 8.6, z = 15}, "ghidorah:ghidorah")
			local e = g:get_luaentity()
			e._regrow_time = 6
			L("spawned " .. tostring(e ~= nil))
			local m
			for t = 1, 54 do
				core.after(t, function()
					e = g:get_luaentity()
					if not e then L(("t=%d GHIDORAH gone"):format(t)); return end
					local p = g:get_pos()
					local heads = {}
					for _, h in ipairs(HEADS) do
						local o = g:get_bone_override("head_" .. h)
						local sc = o and o.scale and o.scale.vec and o.scale.vec.x or 1
						heads[#heads + 1] = ("%s:%d%s"):format(h, e._head_hp and e._head_hp[h] or -1,
							(e._head_regrow and e._head_regrow[h]) and ("(regrow %.0f,scale %.2f)"):format(e._head_regrow[h], sc) or "")
					end
					local tgt = e.attack and (e.attack:is_player() and "player" or e.attack:get_luaentity().name) or "-"
					L(("t=%d pos=%s alt=%.1f flying=%s land=%s anim=%s target=%s hp=%d beam=%s heads=%s dead=%s")
						:format(t, core.pos_to_string(vector.round(p)), p.y - kaiju_core.ground_y(p), tostring(e._flying),
						tostring(e._land), tostring(e._current_animation), tgt, e.health, tostring(e._beam_time ~= nil),
						table.concat(heads, " "), tostring(e.dead)))
				end)
			end
			-- real arrows from the player (he stands still in his second beam volley): one at
			-- the centre head, one at the chest
			core.after(13.4, function()
				local eye = vector.offset(player:get_pos(), 0, 1.6, 0)
				for _, aim in ipairs({e._hitbox_c:get_pos(), e._hitbox_chest:get_pos()}) do
					mcl_bows.shoot_arrow("mcl_bows:arrow", eye, vector.direction(eye, aim), 0, player, POWER, 10)
				end
				local c, body = e._head_hp.c, e.health
				core.after(0.5, function()
					L(("arrows: centre head %d -> %d, body %d -> %d (anim=%s)"):format(c, e._head_hp.c, body, e.health, tostring(e._current_animation)))
				end)
			end)
			core.after(14, function()
				local hp = e and e._head_hp and e._head_hp.l
				hit_at(g, "l", 30) -- only wounds it
				L("wounded left head -> head hp " .. tostring(e._head_hp.l) .. ", body hp " .. e.health)
				hit_at(g, "l", 500)
				L("hit left head (" .. tostring(hp) .. " hp) -> body hp " .. g:get_luaentity().health)
			end)
			core.after(24, function()
				m = core.add_entity({x = 20, y = 30, z = -10}, "mothra:mothra") -- within his view range (64)
				L("mothra spawned")
			end)
			core.after(40, function()
				if m and m:is_valid() then m:remove() end
				L("mothra removed")
			end)
			core.after(52, function()
				for _, h in ipairs(HEADS) do hit_at(g, h, 500) end
				L("hit all three heads")
			end)
		end)
	end)
	core.after(60, function() core.request_shutdown("done") end)
end)
