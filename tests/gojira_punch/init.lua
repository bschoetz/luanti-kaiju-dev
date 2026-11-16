-- Punches must not stop Gojira (knock_back = false, projectile_knockback no-op), and losing
-- the target must end a bulldoze (attack_end clears _bulldoze_time and its straight-line goal).
local function L(s) core.log("action", "[test] " .. s) end
local function hspeed(o) local v = o:get_velocity(); return math.sqrt(v.x * v.x + v.z * v.z) end

core.register_globalstep(function()
	for _, pl in ipairs(core.get_connected_players()) do if pl:get_hp() > 0 then pl:set_hp(20) end end
end)

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function()
		player:set_pos({x = 0, y = 9, z = -20})
		core.after(2, function()
			local g = core.add_entity({x = 0, y = 8.6, z = 25}, "gojira:gojira")
			local e = g:get_luaentity()
			e._breath_cooldown = 1e9 -- keep him walking, no fire breath
			local function wait()
				e = g:get_luaentity()
				if not (e and e.attack and hspeed(g) > 2) then return core.after(0.3, wait) end
				L("locked on, walking")
				-- 1) melee punches and one projectile knockback while he walks
				for i = 1, 4 do
					core.after(i * 0.7, function()
						local before, hp = hspeed(g), e.health
						if i < 4 then
							g:punch(player, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = 10}}, vector.new(0, 0, 1))
						else
							e:projectile_knockback(1, vector.new(0, 0, 1))
						end
						L(("%s %d: speed before=%.2f after=%.2f hp %d->%d"):format(i < 4 and "punch" or "projectile",
							i, before, hspeed(g), hp, e.health))
						core.after(0.25, function() L(("  0.25 s later speed=%.2f"):format(hspeed(g))) end)
					end)
				end
				-- control: stock mcl_mobs knockback (what the fix disables) zeroes his velocity
				core.after(3.2, function()
					local before = hspeed(g)
					e.knock_back = true
					g:punch(player, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = 10}}, vector.new(0, 0, 1))
					e.knock_back = false
					L(("control (stock knock_back=true): speed before=%.2f after=%.2f"):format(before, hspeed(g)))
				end)
				-- 2) force a bulldoze, then drop the target (creative players are not valid targets)
				core.after(3.5, function()
					e._bulldoze_time = 6
					e:cancel_navigation()
					e:go_to_stupidly(player:get_pos(), 1)
					L(("bulldoze forced: _bulldoze_time=%s"):format(tostring(e._bulldoze_time)))
					mcl_gamemode.set_gamemode(player, "creative")
				end)
				for t = 1, 3 do
					core.after(3.5 + t, function()
						L(("after target loss t=%d: attack=%s _bulldoze_time=%s stupid_target=%s"):format(t,
							tostring(e.attack), tostring(e._bulldoze_time), tostring(e.stupid_target and core.pos_to_string(e.stupid_target))))
					end)
				end
			end
			wait()
		end)
	end)
	core.after(20, function() core.request_shutdown("done") end)
end)
