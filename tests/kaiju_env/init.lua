-- Lava and walls hurt the kaiju alike on both games (VoxeLibre: the layer's own check,
-- kaiju_core/vl.lua). Four passive kaiju pinned in place for 4 s, smashing off:
--   Mothra and a Gojira over lava sources: she takes 4 per 0.5 s and burns, he nothing
--   (fire resistant);
--   a Gojira and a Ghidorah with a cobble column inside the body, up through the head: he
--   suffocates (1 per 0.5 s), Ghidorah never does (his eyes are above his box).
-- Good: "RESULT ok".
local T = kaiju_test
local pinned = {}
core.register_globalstep(function()
	for obj, pos in pairs(pinned) do
		if obj:is_valid() then obj:set_pos(pos); obj:set_velocity(vector.zero()) end
	end
end)
local function passive(name, x)
	local pos = vector.new(x, 8.6, 20)
	local obj = core.add_entity(pos, name)
	local e = obj:get_luaentity()
	e.attack_type, e._targeting_rules, e.ai_functions = false, {}, {}
	pinned[obj] = pos
	return e
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(4, function()
		player:set_pos(vector.new(10, 9.5, 0))
		local m, g, g2, k = passive("mothra:mothra", -20), passive("gojira:gojira", 0), passive("gojira:gojira", 20), passive("ghidorah:ghidorah", 40)
		core.after(2, function()
			for _, x in ipairs({-20, 0}) do T.fill(vector.new(x - 1, 9, 19), vector.new(x + 1, 9, 21), "mcl_core:lava_source") end
			for _, x in ipairs({20, 40}) do T.fill(vector.new(x, 15, 20), vector.new(x, 23, 20), "mcl_core:cobble") end
			local hp = {m.health, g.health, g2.health, k.health}
			core.after(4, function()
				local r = {mothra_lava = hp[1] - m.health, gojira_lava = hp[2] - g.health,
					gojira_wall = hp[3] - g2.health, ghidorah_wall = hp[4] - k.health}
				T.result(r, {"mothra_lava", "gojira_lava", "gojira_wall", "ghidorah_wall"},
					{{"mothra_lava", {16, 80}}, {"gojira_lava", {0, 0}}, {"gojira_wall", {4, 12}}, {"ghidorah_wall", {0, 0}}})
				core.request_shutdown("done")
			end)
		end)
	end)
end)
