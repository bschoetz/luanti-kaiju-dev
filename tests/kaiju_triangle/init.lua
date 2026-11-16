-- Three-way fight: Gojira and Mothra team up against King Ghidorah (player in creative,
-- so nobody targets the player). Logs every kaiju's target and HP once a second, until
-- Ghidorah or Gojira is dead: "END winner=allies|ghidorah ..." (balance: the allies should
-- win with Gojira alive, see kaiju/ghidorah/README.md, Balance).
local function L(s) core.log("action", "[test] " .. s) end
local function tname(e)
	local a = e and e.attack
	if not a or not a:is_valid() then return "-" end
	return a:is_player() and "player" or a:get_luaentity().name:gsub(":.*", "")
end
local function hp(e) return e and e.health or -1 end
local LIMIT = 140 -- seconds; the fight usually ends after 60 to 100
local ended

-- Gojira's breaths: all, those from closer than 9 nodes (feet to feet; the old minimum)
-- and upward ones from beyond 32 (the old maximum).
local breaths, close, up_far, breathing = 0, 0, 0, false
local function count_breaths(g)
	core.register_globalstep(function()
		local e, t = g:get_luaentity(), nil
		if not e then return end
		if e._breath_time and not breathing then
			t = e.attack and e.attack:is_valid() and e.attack:get_pos()
			local d = t and vector.distance(g:get_pos(), t) or 20
			breaths = breaths + 1
			if d < 9 then close = close + 1 end
			if d > 32 and e._breath_up then up_far = up_far + 1 end
		end
		breathing = e._breath_time ~= nil
	end)
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function()
		local list = {}
		for x = -1, 1 do for z = -51, -49 do for y = 9, 28 do list[#list + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(list, {name = "mcl_core:cobble"})
		player:set_pos({x = 0, y = 29, z = -50}); player:set_look_horizontal(0); player:set_look_vertical(0.05)
		core.after(2, function()
			local g = core.add_entity({x = -12, y = 8.6, z = 10}, "gojira:gojira")
			local k = core.add_entity({x = 12, y = 8.6, z = 25}, "ghidorah:ghidorah")
			local m = core.add_entity({x = -20, y = 30, z = 0}, "mothra:mothra")
			L("spawned")
			count_breaths(g)
			local done
			for t = 1, LIMIT do
				core.after(t, function()
					if done then return end
					local ge, ke, me = g:get_luaentity(), k:get_luaentity(), m:get_luaentity()
					local kp = k:get_pos()
					local gp = g:get_pos()
					L(("t=%d GOJIRA hp=%d target=%s anim=%s dist=%.1f | MOTHRA hp=%d target=%s | GHIDORAH hp=%d target=%s flying=%s alt=%.0f anim=%s heads=%s")
						:format(t, hp(ge), tname(ge), tostring(ge and ge._current_animation),
						gp and kp and math.sqrt((gp.x - kp.x) ^ 2 + (gp.z - kp.z) ^ 2) or -1, hp(me), tname(me),
						hp(ke), tname(ke), tostring(ke and ke._flying), kp and kp.y - kaiju_core.ground_y(kp) or -1,
						tostring(ke and ke._current_animation),
						ke and ke._head_hp and ("%d/%d/%d"):format(ke._head_hp.c, ke._head_hp.l, ke._head_hp.r) or "-"))
					-- the fight is over when Ghidorah or Gojira is dead; 8 more samples show the truce
					local gd, kd = not ge or ge.dead, not ke or ke.dead
					if (gd or kd or t == LIMIT) and not ended then
						ended = t
						L(("END winner=%s t=%d gojira=%d mothra=%d ghidorah=%d breaths=%d close=%d up_far=%d"):format(
							kd and (gd and "draw" or "allies") or gd and "ghidorah" or "none", t,
							math.max(hp(ge), 0), math.max(hp(me), 0), math.max(hp(ke), 0), breaths, close, up_far))
						local nav = kaiju_core._vl_nav_stats -- (VoxeLibre: the path searches, for information)
						if nav then
							L(("NAV plans=%d partial=%d failed=%d avg_us=%d max_us=%d"):format(nav.plans, nav.partial, nav.failed,
								nav.total_us / math.max(nav.plans, 1), nav.max_us))
						end
					end
					if ended and t >= ended + 8 then
						done = true
						core.request_shutdown("done")
					end
				end)
			end
		end)
	end)
	core.after(LIMIT + 10, function() core.request_shutdown("done") end)
end)
