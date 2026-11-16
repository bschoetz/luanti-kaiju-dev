-- What Gojira can reach: no gap between his bite and his breath, and flyers up to 48 nodes.
-- Four phases, each with a fresh Gojira 30 nodes from a survival player pinned in place:
--   ring     the player on a 1-node pillar inside an obsidian ring (radius 5, 3 high) that
--            stops him about 8 nodes away, beyond his bite (7): he breathes fire. (The
--            breath is held back until he stands at the ring.)
--   chest    the player 8 above the ground, breath off: he walks below and bites (the bite
--            is measured from his body's axis, not from his feet).
--   head     the player 26.5 above the ground (12 above his head): he breathes upwards.
--   high     the player 40 above the ground: he breathes upwards (range 48).
-- Checked: breaths and their distance in "ring", bites in "chest", upward breaths in
-- "head" and "high", flames that set the player on fire in "ring" and "high", and that
-- he never burns himself. Good: "RESULT ok".
local T = kaiju_test
local GROUND = 8.5
local PHASES = {
	{name = "ring", h = 1, ring = true, hold_breath = true, time = 24}, -- (time for three breaths: not every one hits)
	{name = "chest", h = 8, no_breath = true, time = 14},
	{name = "head", h = 26.5, time = 12},
	{name = "high", h = 40, time = 18},
}
local CENTRE = vector.new(0, 9, -10)
local spot -- where the player is pinned
local r = {}

local function ring(name)
	local list = {}
	for x = -6, 6 do for z = -6, 6 do
		local d = math.sqrt(x * x + z * z)
		if d >= 4.5 and d < 5.5 then
			for y = 0, 2 do list[#list + 1] = vector.offset(CENTRE, x, y, z) end
		end
	end end
	core.bulk_set_node(list, {name = name})
end

local gojira, phase, breathing, at_ring
core.register_globalstep(function()
	local pl = core.get_connected_players()[1]
	if not pl then return end
	if pl:get_hp() > 0 then pl:set_hp(20) end
	if spot and vector.distance(pl:get_pos(), spot) > 0.5 then pl:set_pos(spot) end -- (bites knock)
	local e = gojira and gojira:get_luaentity()
	if not e then return end
	local n = phase.name
	if mcl_burning.is_burning(pl) then r[n .. "_burned"] = true end
	local p = gojira:get_pos()
	-- (released a second after he arrives, and only while he is that close: he may
	-- walk off again to look for a way around the ring)
	if phase.hold_breath and at_ring ~= true and T.flat(p, spot) <= 8.7 then
		at_ring = at_ring or core.get_us_time()
		if core.get_us_time() - at_ring > 1e6 then
			at_ring = true
			e._breath_cooldown = 0
		end
	end
	if e._breath_time and not breathing then
		local d = vector.distance(p, pl:get_pos())
		r[n .. "_breaths"] = r[n .. "_breaths"] + 1
		if e._breath_up then r[n .. "_breaths_up"] = r[n .. "_breaths_up"] + 1 end
		r[n .. "_first_dist"] = r[n .. "_first_dist"] or d
		T.log(("%s: breath at dist %.1f, flat %.1f, up=%s"):format(n, d, T.flat(p, spot), tostring(e._breath_up)))
	end
	breathing = e._breath_time ~= nil
end)

local function run(player, i)
	phase = PHASES[i]
	if not phase then
		local keys, n = {}, 0
		for _, ph in ipairs(PHASES) do
			for _, k in ipairs({"breaths", "breaths_up", "first_dist", "bites", "burned", "gojira_hp"}) do
				n = n + 1
				keys[n] = ph.name .. "_" .. k
			end
		end
		T.result(r, keys, {
			{"ring_breaths", {1, 9}}, {"ring_first_dist", {7, 9}}, {"ring_burned", true}, {"ring_gojira_hp", {500, 500}},
			{"chest_bites", {1, 99}}, {"chest_gojira_hp", {500, 500}},
			{"head_breaths_up", {1, 9}}, {"head_gojira_hp", {500, 500}},
			{"high_breaths_up", {1, 9}}, {"high_burned", true}, {"high_gojira_hp", {500, 500}},
		})
		core.request_shutdown("done")
		return
	end
	local n = phase.name
	r[n .. "_breaths"], r[n .. "_breaths_up"], r[n .. "_bites"] = 0, 0, 0
	mcl_burning.extinguish(player)
	if phase.ring then
		ring("mcl_core:obsidian")
		core.set_node(CENTRE, {name = "mcl_core:obsidian"})
	end
	spot = vector.new(CENTRE.x, GROUND + phase.h, CENTRE.z)
	player:set_pos(spot)
	core.after(1, function()
		gojira = core.add_entity(vector.new(0, GROUND + 0.1, 20), "gojira:gojira")
		local e = gojira:get_luaentity()
		breathing, at_ring = false, false
		e._breath_cooldown = (phase.no_breath or phase.hold_breath) and 1e9 or 0
		local bite = e.custom_attack
		e.custom_attack = function(...) r[n .. "_bites"] = r[n .. "_bites"] + 1; return bite(...) end
		core.after(phase.time, function()
			r[n .. "_gojira_hp"] = e.health
			local p = gojira:get_pos()
			T.log(("%s: end, flat %.1f, dist %.1f"):format(n, T.flat(p, spot), vector.distance(p, spot)))
			gojira:remove()
			gojira = nil
			if phase.ring then ring("air"); core.remove_node(CENTRE) end
			-- (flames in flight, fire on the ground)
			core.after(3, function() run(player, i + 1) end)
		end)
	end)
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(3, function()
		player:set_physics_override({gravity = 0})
		run(player, 1)
	end)
	core.after(150, function() core.request_shutdown("timeout") end)
end)
