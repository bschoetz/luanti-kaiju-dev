-- Gojira against King Ghidorah on the ground: their bodies must not end up inside each
-- other. Logs the horizontal distance between their centres twice a second for 45 s.
-- Their collision boxes are 2.4 and 2.6 nodes half-width, so the bodies touch at 5.0.
-- Good: the last line is "RESULT ok".
local function L(s) core.log("action", "[test] " .. s) end
local MIN_GAP = 5.0   -- 2.4 + 2.6: the collision boxes touch
local TOLERANCE = 0.5 -- the boxes are axis-aligned squares, the distance is centre to centre

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function()
		local list = {}
		for x = -1, 1 do for z = -41, -39 do for y = 9, 22 do list[#list + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(list, {name = "mcl_core:cobble"})
		player:set_pos({x = 0, y = 23, z = -40}); player:set_look_horizontal(0); player:set_look_vertical(0.15)
		core.after(2, function()
			local g = core.add_entity({x = -15, y = 8.6, z = 15}, "gojira:gojira")
			local k = core.add_entity({x = 15, y = 8.6, z = 15}, "ghidorah:ghidorah")
			L("spawned")
			local n, inside, min, ground, last = 0, 0, math.huge, 0, nil
			local recover = math.huge
			local hp30, hp_end -- {gojira, ghidorah} at 30 s and at the last sample
			local turn_g, turn_k = 0, 0
			local function sample(i)
				local ge, ke = g:get_luaentity(), k:get_luaentity()
				if not (ge and ke) or ge.dead or ke.dead then return end
				local a, b = g:get_pos(), k:get_pos()
				local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
				local yg, yk = g:get_yaw(), k:get_yaw()
				local function turned(y, y0) return math.abs((y - y0 + math.pi) % (2 * math.pi) - math.pi) end
				local dg, dk = last and turned(yg, last[1]) or 0, last and turned(yk, last[2]) or 0
				last = {yg, yk}
				n = n + 1
				local forced = i > 50 and i <= 56 -- the 3 s after Gojira was put inside him
				if forced and d >= MIN_GAP - TOLERANCE then recover = math.min(recover, i / 2 - 25) end
				if i == 60 then hp30 = {ge.health, ke.health} end
				hp_end = {ge.health, ke.health}
				if not ke._flying and not forced then
					ground = ground + 1
					min = math.min(min, d)
					if d < MIN_GAP - TOLERANCE then inside = inside + 1 end
					turn_g, turn_k = turn_g + dg, turn_k + dk
				end
				if i % 2 == 0 then
					L(("t=%.0f dist=%.1f | GOJIRA hp=%d anim=%s turned=%d | GHIDORAH hp=%d anim=%s flying=%s turned=%d"):format(i / 2, d,
						ge.health, tostring(ge._current_animation), math.deg(dg), ke.health, tostring(ke._current_animation),
						tostring(ke._flying), math.deg(dk)))
				end
			end
			for i = 1, 90 do core.after(i / 2, sample, i) end
			-- 25 s: put Gojira right inside Ghidorah (as if he had landed on him). They must
			-- come apart again; the samples of the next 3 s don't count.
			core.after(25.1, function()
				if not (g:is_valid() and k:is_valid()) then return end
				g:set_pos(vector.offset(k:get_pos(), 0.5, 0, 0.5))
				L("gojira placed inside ghidorah")
			end)
			core.after(45.5, function()
				L(("samples=%d on the ground=%d | min dist=%.1f | closer than %.1f: %d | mean turn per 0.5 s: gojira %.0f deg, ghidorah %.0f deg")
					:format(n, ground, min, MIN_GAP - TOLERANCE, inside, math.deg(turn_g / math.max(ground, 1)), math.deg(turn_k / math.max(ground, 1))))
				L(recover < math.huge and ("apart again %.1f s after being put inside each other"):format(recover)
					or "still inside each other 3 s after being put there")
				local fails = {}
				if ground < 30 then fails[#fails + 1] = "fewer than 30 ground samples" end
				if recover == math.huge then fails[#fails + 1] = "they did not come apart after being put inside each other" end
				-- stuck would mean: standing there without hurting each other
				if not (hp30 and hp_end[1] < hp30[1] and hp_end[2] < hp30[2]) then
					fails[#fails + 1] = "they stopped fighting (HP unchanged in the last 15 s)"
				end
				if inside > 0 then fails[#fails + 1] = inside .. " samples with the bodies inside each other" end
				L(#fails == 0 and "RESULT ok" or "RESULT FAIL: " .. table.concat(fails, "; "))
			end)
		end)
	end)
	core.after(52, function() core.request_shutdown("done") end)
end)
