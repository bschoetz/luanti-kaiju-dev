-- Cthulhu at home in a real ocean (mapgen v7, seed 7) with natural mob spawning on, for
-- 80 s; the player stands outside his territory. Fish, squid, bats and whatever lives in
-- the caves under the sea must not wake him; animals on the beach may (that is the
-- design). Every target he takes is logged and must be a land mob under the open sky or in
-- open water, and he must never be further than his leash from home. Which mobs spawn
-- differs from run to run. Ends with a VALUES and a RESULT line (see tests/README.md).
local T = kaiju_test
local L, flat = T.log, T.flat
local SHORE = T.OCEAN_SHORE

T.keep_players_alive()

-- as Cthulhu's own test: the natural light above the water the mob is in
local function sky_light(pos)
	local p, n = vector.round(vector.offset(pos, 0, 0.5, 0)), 0
	while n < 64 and core.get_item_group(core.get_node(p).name, "water") > 0 do p.y, n = p.y + 1, n + 1 end
	return core.get_natural_light(p, 0.5) or 0
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function() T.ocean(function()
		local spot = T.on_ground(SHORE.x, SHORE.z)
		local c = core.add_entity(vector.offset(spot, 0, -0.4, 0), "cthulhu:cthulhu")
		local e = c:get_luaentity()
		local home = vector.new(e._home)
		local inland = vector.normalize(vector.new(spot.x - home.x, 0, spot.z - home.z))
		player:set_pos(T.on_ground(home.x + inland.x * 60, home.z + inland.z * 60))
		c:set_pos(vector.offset(home, 0, 0.1, 0)) -- (skip the walk home)
		local t, last = 0, nil
		local r = {targets = 0, bad_targets = 0, engaged = 0, max_home_dist = 0}
		local seen, spared = {}, {} -- mobs that were in his territory, by name
		local function tick()
			e = c:get_luaentity()
			if not e then L("RESULT FAIL: cthulhu is gone"); core.request_shutdown("done"); return end
			t = t + 0.5
			local p = c:get_pos()
			r.max_home_dist = math.max(r.max_home_dist, flat(p, home))
			local a = e.attack
			if a and a:is_valid() then
				r.engaged = r.engaged + 0.5
				if a ~= last then
					local ent, ap = a:get_luaentity(), a:get_pos()
					local light = sky_light(ap)
					local ok = a:is_player() or (ent and not (ent.swims or ent.breathes_in_water or ent.amphibious or ent.airborne) and light >= 8)
					r.targets = r.targets + 1
					if not ok then r.bad_targets = r.bad_targets + 1 end
					L(("t=%.1f TARGET %s at %s, %.0f from home, sky light %d: %s"):format(t, T.name_of(a), core.pos_to_string(ap, 1),
						flat(ap, home), light, ok and "ok" or "BAD"))
				end
			end
			last = a
			if t % 5 == 0 then
				for obj in core.objects_inside_radius(home, 70) do
					local ent = obj:get_luaentity()
					if ent and ent.is_mob and obj ~= c and flat(obj:get_pos(), home) <= 48 then
						seen[ent.name] = true
						if obj ~= a and e.attack == nil then spared[ent.name] = true end
					end
				end
				L(("t=%d pos=%.0f,%.1f,%.0f home_dist=%.1f target=%s anim=%s hp=%d"):format(t, p.x, p.y, p.z, flat(p, home),
					T.name_of(a), tostring(e._current_animation), e.health))
			end
			if t >= 80 then
				local function names(set)
					local l = {}
					for k in pairs(set) do l[#l + 1] = k end
					table.sort(l)
					return #l > 0 and table.concat(l, ",") or "-"
				end
				L("mobs seen in his territory: " .. names(seen))
				L("of these, there while he had no target: " .. names(spared))
				T.result(r, {"targets", "bad_targets", "engaged", "max_home_dist"}, {{"bad_targets", {0, 0}}, {"max_home_dist", {0, 80}}})
				core.request_shutdown("done")
				return
			end
			core.after(0.5, tick)
		end
		core.after(3, tick)
	end) end)
end)
