local function L(s) core.log("action", "[test] " .. s) end
-- oak: Mineclonia's names, else VoxeLibre's (once every mod has registered its nodes)
local TREE, LEAVES
core.register_on_mods_loaded(function()
	TREE = core.registered_nodes["mcl_trees:tree_oak"] and "mcl_trees:tree_oak" or "mcl_core:tree"
	LEAVES = core.registered_nodes["mcl_trees:leaves_oak"] and "mcl_trees:leaves_oak" or "mcl_core:leaves"
end)
local def = core.registered_entities["gojira:gojira"]
local was_bulldozing = false
local orig_attack = def.attack_melee
def.attack_melee = function(self, ...)
	local r = orig_attack(self, ...)
	local b = self._bulldoze_time ~= nil
	if b ~= was_bulldozing then
		local pp = self.object:get_pos()
		L(("BULLDOZE %s at %s y=%.2f under=%s"):format(b and "start" or "end", core.pos_to_string(vector.round(pp)), pp.y, core.get_node(vector.round(vector.offset(pp, 0, -0.6, 0))).name))
	end
	was_bulldozing = b
	return r
end

local CHEST = vector.new(0, 9, 3)
local function count(name, p1, p2)
	local _, c = core.find_nodes_in_area(p1, p2, name); return c[name] or 0
end
local function report(tag)
	local items = {}
	for _, obj in ipairs(core.get_objects_inside_radius(vector.new(0, 9, 3), 25)) do
		local e = obj:get_luaentity()
		if e and e.name == "__builtin:item" then
			local st = ItemStack(e.itemstring)
			items[st:get_name()] = (items[st:get_name()] or 0) + st:get_count()
		end
	end
	local parts = {}
	for k, v in pairs(items) do parts[#parts + 1] = k .. "=" .. v end
	table.sort(parts)
	local floating = 0
	for _, p in ipairs(core.find_nodes_in_area(vector.new(-12, 10, -12), vector.new(12, 30, 30), "mcl_core:sand")) do
		if core.get_node(vector.offset(p, 0, -1, 0)).name == "air" then floating = floating + 1 end
	end
	L(("%s: chest=%s wall_stone=%d trunks=%d sand_nodes=%d floating_sand=%d items={%s}"):format(tag,
		core.get_node(CHEST).name .. " hive=" .. core.get_node(vector.new(-1, 9, 4)).name .. " nest=" .. core.get_node(vector.new(1, 9, 4)).name, count("mcl_core:stone", vector.new(-9, 9, -9), vector.new(9, 28, 9)),
		count(TREE, vector.new(-12, 9, 12), vector.new(12, 16, 28)),
		count("mcl_core:sand", vector.new(-12, 9, -12), vector.new(12, 30, 30)), floating, table.concat(parts, ", ")))
end

local function fill(p1, p2, name)
	local list = {}
	for x = p1.x, p2.x do for y = p1.y, p2.y do for z = p1.z, p2.z do list[#list + 1] = vector.new(x, y, z) end end end
	core.bulk_set_node(list, {name = name})
end

local function build_ring()
	-- stone ring around the player, 20 high
	for _, r in ipairs({{-9, -9, 9, -9}, {-9, 9, 9, 9}, {-9, -9, -9, 9}, {9, -9, 9, 9}}) do
		fill(vector.new(r[1], 9, r[2]), vector.new(r[3], 28, r[4]), "mcl_core:stone")
	end
end
local function build_outside()
	-- house inside the ring with a chest and a sand pile on the roof
	fill(vector.new(-3, 9, 1), vector.new(3, 12, 6), "mcl_core:cobble")
	fill(vector.new(-2, 9, 2), vector.new(2, 12, 5), "air")
	fill(vector.new(-3, 13, 1), vector.new(3, 13, 6), "mcl_core:wood")
	fill(vector.new(-1, 14, 2), vector.new(1, 16, 4), "mcl_core:sand")
	core.set_node(CHEST, {name = "mcl_chests:chest_small"})
	-- dig callbacks that assume a player digger (crashed the server before kaiju_core caught it)
	core.set_node(vector.new(-1, 9, 4), {name = "mcl_beehives:beehive"})
	core.set_node(vector.new(1, 9, 4), {name = "mcl_beehives:bee_nest"})
	local inv = core.get_meta(CHEST):get_inventory()
	inv:add_item("main", "mcl_core:gold_ingot 17")
	inv:add_item("main", "mcl_core:emerald 5")
	-- forest outside the ring
	for x = -9, 9, 3 do
		for z = 14, 26, 4 do
			fill(vector.new(x - 1, 13, z - 1), vector.new(x + 1, 16, z + 1), LEAVES)
			fill(vector.new(x, 9, z), vector.new(x, 14, z), TREE)
		end
	end
end

core.register_globalstep(function()
	for _, pl in ipairs(core.get_connected_players()) do if pl:get_hp() > 0 then pl:set_hp(20) end end
end)

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	player:set_pos({x = 0, y = 9, z = -6})
	player:set_look_horizontal(0); player:set_look_vertical(-0.45)
	core.after(1, function()
		local g = core.add_entity({x = 0, y = 8.6, z = 36}, "gojira:gojira")
		L("griefing=" .. tostring(kaiju_core.mob_griefing("gojira:gojira")))
		-- close the ring only once he has locked on
		local function wait()
			local e = g:get_luaentity()
			if e and e.attack then
				build_ring(); build_outside(); report("world built, target locked")
			else core.after(0.5, wait) end
		end
		wait()
	end)
	for t = 10, 60, 10 do core.after(t, function() report("t=" .. t) end) end
	-- Gojira's track, to see whether he walked through the house (chest at 0,9,3)
	for t = 2, 40, 2 do core.after(t, function()
		for _, o in pairs(core.luaentities) do
			if o.name == "gojira:gojira" then
				local p = o.object:get_pos()
				L(("track t=%d pos=%s y=%.2f anim=%s"):format(t, core.pos_to_string(vector.round(p)), p.y, tostring(o._current_animation)))
			end
		end
	end) end
	core.after(62, function() core.request_shutdown("done") end)
end)
