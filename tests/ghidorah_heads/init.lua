-- King Ghidorah's heads in a real brawl, seen from close by (player in creative): the
-- fight opens with beams over 34 nodes, then he bites Gojira while the side heads beam
-- the circling Mothra on their own. Logs once a second; bearing/elev say where Mothra is
-- relative to his facing (the heads turn at most 60 degrees).
-- Screenshots: tests/run.sh ghidorah_heads 56
-- Good: side=true volleys while anim is punch/stand/walk, and MOTHRA hp drops in those
-- where l-> or r-> shows mothra. heads= rarely drops below 120: a bite of Gojira only
-- lands on a head that is down at his height (lowered for the beams).
-- At t=40 "COUNTS side=N melee_full=M": samples (after t=8) in a side volley, and in a full
-- volley at a Gojira closer than 10 nodes. No pass/fail: the brawl takes a different course
-- every run (usually side 4-13 and melee_full 0; if he flies after Mothra all the time,
-- side is 0; a volley at a Gojira who breathes fire from 8 nodes gives melee_full 2-3).
-- After the 40 samples: "severed left head: ... 0 with a target" ("inconclusive" if no other
-- enemy was in reach of the side heads), "regrown left head: ... aim cache cleared=true",
-- then the aim cache equal to the override, "stuck take-off: flying=true _bulldoze_time=nil".
local function L(s) core.log("action", "[test] " .. s) end
local function tname(a)
	if not a or not a:is_valid() then return "-" end
	return a:is_player() and "player" or a:get_luaentity().name:gsub(":.*", "")
end
local function hp(e) return e and e.health or -1 end
-- Where obj is, seen from Ghidorah's chest: bearing relative to his facing, elevation, distance.
local function seen_from(k, obj)
	local d = vector.subtract(obj:get_pos(), vector.offset(k:get_pos(), 0, 16, 0))
	return (math.atan2(d.z, d.x) - math.pi / 2 - k:get_yaw() + math.pi) % (2 * math.pi) - math.pi,
		math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z)), vector.length(d)
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function()
		local list = {}
		for x = -1, 1 do for z = -27, -25 do for y = 9, 16 do list[#list + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(list, {name = "mcl_core:cobble"})
		player:set_pos({x = 0, y = 17, z = -26}); player:set_look_horizontal(0); player:set_look_vertical(-0.1)
		core.after(2, function()
			local g = core.add_entity({x = -17, y = 8.6, z = 14}, "gojira:gojira")
			local k = core.add_entity({x = 17, y = 8.6, z = 14}, "ghidorah:ghidorah")
			local m = core.add_entity({x = 0, y = 30, z = 30}, "mothra:mothra")
			L("spawned")
			local res = {side = 0, melee_full = 0}
			for t = 1, 40 do
				core.after(t, function()
					local ge, ke, me = g:get_luaentity(), k:get_luaentity(), m:get_luaentity()
					if not ke then L(("t=%d GHIDORAH gone"):format(t)); return end
					-- where Mothra is, seen from his chest: bearing relative to his facing, elevation
					local bearing, elev = 0, 0
					if me then bearing, elev = seen_from(k, m) end
					-- after the opening: seconds with a side volley, and with a full volley at a
					-- Gojira who is in melee (a gust only knocked him a few nodes away)
					local dist = g:is_valid() and kaiju_test.flat(k:get_pos(), g:get_pos()) or -1
					if t >= 8 and ke._beam_time then
						if ke._beam_side then
							res.side = res.side + 1
						elseif tname(ke.attack) == "gojira" and dist < 10 then
							res.melee_full = res.melee_full + 1
						end
					end
					if t == 40 then L(("COUNTS side=%d melee_full=%d"):format(res.side, res.melee_full)) end
					L(("t=%d GOJIRA hp=%d dist=%.1f | MOTHRA hp=%d bearing=%d elev=%d | GHIDORAH hp=%d target=%s anim=%s beam=%s side=%s l->%s r->%s heads=%d/%d/%d")
						:format(t, hp(ge), dist, hp(me), math.deg(bearing), math.deg(elev), hp(ke), tname(ke.attack), tostring(ke._current_animation),
						tostring(ke._beam_time ~= nil), tostring(ke._beam_side), tname(ke._head_target_l), tname(ke._head_target_r),
						ke._head_hp.c, ke._head_hp.l, ke._head_hp.r))
				end)
			end
			-- 41 s: sever the left head (regrowing in 4 s). A stump must not pick a target.
			core.after(41, function()
				local ke = k:get_luaentity()
				if not ke or ke.dead then L("left head: skipped, ghidorah is dead"); return end
				ke._regrow_time = 4
				mcl_util.deal_damage(ke._hitbox_l, 500, {type = "mob"})
				-- `with` only means something if a head could have had a target of its own:
				-- an enemy other than the main target, within beam range and the 60 degree cone
				local with, available = 0, 0
				for i = 1, 14 do
					core.after(i * 0.25, function()
						if not k:is_valid() then return end
						if ke._head_target_l then with = with + 1 end
						for _, o in ipairs({g, m}) do
							local e = o:get_luaentity()
							if e and not e.dead and o ~= ke.attack then
								local bearing, elev, dist = seen_from(k, o)
								if dist <= 40 and math.abs(bearing) <= math.rad(60) and math.abs(elev) <= math.rad(60) then
									available = available + 1
									break
								end
							end
						end
						if i == 14 then
							L(("severed left head: 14 samples, %d with a target, r->%s%s"):format(with, tname(ke._head_target_r),
								available == 0 and " -- inconclusive: no other enemy was in reach of the side heads" or
								(" (another enemy in reach in %d samples)"):format(available)))
						end
					end)
				end
				-- Regrown at 45 s: regrowth must clear the aim cache, or aim_head would not send
				-- the rotation again. Aiming is held back from 3.9 s on, so nothing else refills it.
				core.after(3.9, function() ke._aim_timer = 10 end)
				core.after(4.3, function()
					if not k:is_valid() then return end
					L(("regrown left head: hp=%d aim cache cleared=%s"):format(ke._head_hp.l, tostring(ke._aim_l == nil)))
					ke._aim_timer = 0
				end)
				-- ... and once he aims again, the cache must match the bone override that was sent
				core.after(4.8, function()
					if not k:is_valid() then return end
					local a, o = ke._aim_l, k:get_bone_override("head_l")
					L(("regrown left head: aim cache %s, override %.2f/%.2f"):format(
						a and ("%.2f/%.2f"):format(a[1], a[2]) or "nil", -o.rotation.vec.z, -o.rotation.vec.x))
				end)
			end)
			-- 47 s: a stuck (bulldozing) Ghidorah takes off; that must end the bulldoze, or he
			-- takes off again right after landing
			core.after(47, function()
				local ke = k:get_luaentity()
				if not ke or ke.dead or ke._flying then L("stuck take-off: skipped (dead or flying)"); return end
				ke._bulldoze_time, ke._stuck_flights = 6, 0
				local function check(n)
					if not k:is_valid() then return end
					if ke._flying or n == 0 then
						L(("stuck take-off: flying=%s _bulldoze_time=%s stuck_flights=%s"):format(tostring(ke._flying),
							tostring(ke._bulldoze_time), tostring(ke._stuck_flights)))
					else
						core.after(0.5, check, n - 1)
					end
				end
				check(8)
			end)
		end)
	end)
	core.after(53, function() core.request_shutdown("done") end)
end)
