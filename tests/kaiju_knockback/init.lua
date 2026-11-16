-- A kaiju's bite throws a player as far on VoxeLibre as on Mineclonia. (Mineclonia's
-- mcl_player applies its own knockback: 1 + the hitter's _attack_knockback; VoxeLibre
-- leaves players to the engine's, which is the same few nodes per second for every
-- hitter and has no upward part, so friction eats it: kaiju_core/vl.lua adds Mineclonia's.)
-- A passive Gojira (_attack_knockback 3), then a passive Ghidorah (0), bites the standing
-- survival player once; the player's largest horizontal displacement and rise within
-- 1.5 s are logged. Mobs hit by a kaiju keep each game's own knockback: not tested.
-- Run it a second time without damage: Mineclonia throws the player all the same (its
-- gate is the punch's raw damage, not the HP lost), and so must the layer:
--   KAIJU_TEST_CONF='enable_damage = false' tests/run.sh kaiju_knockback
-- Good: "RESULT ok".
local T = kaiju_test
T.keep_players_alive()
local HOME = vector.new(0, 9.0, -10)
local r = {}

-- No AI at all: the test makes the one bite itself. (attack_type must be false, not nil:
-- nil would fall through to the class's "melee".)
local function passive(name, pos)
	local e = core.add_entity(pos, name):get_luaentity()
	e.attack_type, e._targeting_rules, e.ai_functions = false, {}, {}
	return e
end

local function hit(label, e, player, done)
	local p0 = player:get_pos()
	e.attack = player
	e:custom_attack()
	local flat, rise, n = 0, 0, 0
	local function step()
		n = n + 1
		local p = player:get_pos()
		flat, rise = math.max(flat, T.flat(p, p0)), math.max(rise, p.y - p0.y)
		if n < 30 then return core.after(0.05, step) end
		r[label .. "_flat"], r[label .. "_rise"] = flat, rise
		e.object:remove()
		done()
	end
	step()
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	T.log("enable_damage = " .. tostring(core.settings:get_bool("enable_damage")))
	core.after(3, function()
		player:set_pos(HOME)
		core.after(2, function()
			local g = passive("gojira:gojira", vector.new(0, 8.6, -5))
			core.after(1.5, function()
				hit("gojira_player", g, player, function()
					player:set_pos(HOME)
					local h = passive("ghidorah:ghidorah", vector.new(0, 8.6, -4))
					core.after(1.5, function()
						hit("ghidorah_player", h, player, function()
							T.result(r, {"gojira_player_flat", "gojira_player_rise", "ghidorah_player_flat", "ghidorah_player_rise"}, {
								{"gojira_player_flat", {5, 40}}, {"gojira_player_rise", {1, 10}},
								{"ghidorah_player_flat", {0.5, 4}}, {"ghidorah_player_rise", {0.3, 10}},
							})
							core.request_shutdown("done")
						end)
					end)
				end)
			end)
		end)
	end)
	core.after(40, function() core.request_shutdown("timeout") end)
end)
