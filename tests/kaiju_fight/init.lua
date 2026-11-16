local function L(s) core.log("action", "[test] " .. s) end
local function name_of(o) if not o or not o:is_valid() then return "-" end return o:is_player() and "player" or o:get_luaentity().name end
local function ground(p) for pt in core.raycast(vector.offset(p, 0, 1, 0), vector.offset(p, 0, -80, 0), false, true) do if pt.type == "node" then return pt.above.y - 0.5 end end return -999 end
local fdef = core.registered_entities["mothra:mothra"]
L("egg=" .. tostring(core.registered_items["mothra:mothra"] ~= nil))
core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function()
		local list = {}
		for x = -1, 1 do for z = -31, -29 do for y = 9, 18 do list[#list + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(list, {name = "mcl_core:cobble"})
		player:set_pos({x = 0, y = 19, z = -30}); player:set_look_horizontal(0); player:set_look_vertical(-0.05)
		core.after(2, function()
			local m = core.add_entity({x = -25, y = 30, z = 20}, "mothra:mothra")
			local m2 = core.add_entity({x = 25, y = 30, z = 20}, "mothra:mothra")
			core.after(4, function()
				local g = core.add_entity({x = 0, y = 8.6, z = 25}, "gojira:gojira")
				L("spawned mothra=" .. tostring(m:get_luaentity() ~= nil) .. " gojira=" .. tostring(g:get_luaentity() ~= nil))
				for t = 1, 60 do
					core.after(t, function()
						local me, ge = m:get_luaentity(), g:get_luaentity()
						local mp = m:get_pos()
						local s = ("t=%d"):format(t)
						if me and mp then
							s = s .. ("  MOTHRA pos=%s alt=%.1f anim=%s target=%s hp=%d"):format(core.pos_to_string(vector.round(mp)), mp.y - ground(mp), tostring(me._current_animation), name_of(me.attack), me.health)
						else s = s .. "  MOTHRA gone" end
						if ge then
							s = s .. ("  GOJIRA hp=%d target=%s poison=%s anim=%s"):format(ge.health, name_of(ge.attack), tostring(mcl_potions.has_effect(g, "poison")), tostring(ge._current_animation))
						else s = s .. "  GOJIRA gone" end
						local e2 = m2:is_valid() and m2:get_luaentity()
						if e2 then s = s .. ("  MOTHRA2 target=%s hp=%d"):format(name_of(e2.attack), e2.health) end
						s = s .. "  player hp=" .. player:get_hp()
						L(s)
					end)
				end
			end)
		end)
	end)
	core.after(72, function() core.request_shutdown("done") end)
end)
