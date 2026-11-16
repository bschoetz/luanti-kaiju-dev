-- Dig callbacks that assume a player digger must not crash the server when a kaiju smashes
-- their node. mcl_beehives indexes the digger's inventory in creative mode (crashed a real
-- world). Places such nodes right in front of Gojira and runs one smash pass directly.
local function L(s) core.log("action", "[test] " .. s) end
local NODES = {
	{vector.new(0, 9, 4), "mcl_beehives:beehive"},
	{vector.new(1, 9, 4), "mcl_beehives:bee_nest"},
	{vector.new(-1, 9, 4), "mcl_chests:chest_small"},
	{vector.new(0, 10, 4), "mcl_beehives:bee_nest"},
}
core.register_on_joinplayer(function(player)
	core.after(2, function()
		player:set_pos({x = 0, y = 9, z = -12})
		core.after(2, function()
			for _, n in ipairs(NODES) do core.set_node(n[1], {name = n[2]}) end
			core.get_meta(NODES[3][1]):get_inventory():add_item("main", "mcl_core:diamond 3")
			local g = core.add_entity({x = 0, y = 8.6, z = 0}, "gojira:gojira")
			g:set_yaw(0)
			core.after(1, function()
				L("gojira at " .. core.pos_to_string(g:get_pos()) .. " node below: " .. core.get_node(vector.offset(g:get_pos(), 0, -1, 0)).name)
				g:set_yaw(0) -- he may have paced and turned away in the meantime
				kaiju_core.smash(g:get_luaentity(), {lookahead = 4})
				local left = {}
				for _, n in ipairs(NODES) do left[#left + 1] = core.get_node(n[1]).name end
				local items = {}
				for _, o in ipairs(core.get_objects_inside_radius(vector.new(0, 9, 4), 6)) do
					local e = o:get_luaentity()
					if e and e.itemstring then items[#items + 1] = e.itemstring end
				end
				table.sort(items)
				L("after smash: " .. table.concat(left, " ") .. " | items: " .. table.concat(items, ", "))
				core.request_shutdown("done")
			end)
		end)
	end)
end)
