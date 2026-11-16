-- World scenario of tests/compat.sh (not meant for tests/run.sh): the first start spawns the
-- three kaiju, hands out their eggs and saves; later starts report what is left of them.
local function L(s) core.log("action", "[test] " .. s) end
local KAIJU = {"gojira:gojira", "mothra:mothra", "ghidorah:ghidorah"}
local SPAWN = {vector.new(-25, 8.6, 25), vector.new(0, 30, 30), vector.new(25, 8.6, 25)}
local storage = core.get_mod_storage()

local steps = {} -- on_step calls per kaiju: proves the loaded entities are active
for _, name in ipairs(KAIJU) do
	local def = core.registered_entities[name]
	if def then
		local on_step = def.on_step
		def.on_step = function(self, ...)
			steps[name] = (steps[name] or 0) + 1
			return on_step(self, ...)
		end
	end
end

local function report(player)
	local parts, eggs = {}, {}
	for _, name in ipairs(KAIJU) do
		local n, hp, pos = 0, "-", "-"
		for _, e in pairs(core.luaentities) do
			if e.name == name then
				n, hp, pos = n + 1, e.health, core.pos_to_string(vector.round(e.object:get_pos()))
			end
		end
		parts[#parts + 1] = ("%s=%d(hp %s, steps %d, at %s)"):format(name, n, hp, steps[name] or 0, pos)
		eggs[#eggs + 1] = ("%s=%s"):format(name, tostring(core.registered_items[name] ~= nil
			and player:get_inventory():contains_item("main", name)))
	end
	return table.concat(parts, " ") .. " | eggs: " .. table.concat(eggs, " ")
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(4, function()
		if not core.registered_entities["gojira:gojira"] then
			L("kaiju mods NOT loaded | " .. report(player))
		elseif storage:get_int("spawned") == 0 then
			storage:set_int("spawned", 1)
			player:set_pos({x = 0, y = 9, z = 0})
			for i, name in ipairs(KAIJU) do
				core.add_entity(SPAWN[i], name)
				player:get_inventory():add_item("main", name)
			end
		end
		core.after(2, function() -- (not longer: they fight, and flyers leave the active area)
			if core.registered_entities["gojira:gojira"] then
				L((steps["gojira:gojira"] and storage:get_int("loads") > 0 and "loaded: " or "spawned: ") .. report(player))
				storage:set_int("loads", storage:get_int("loads") + 1)
			end
			core.request_shutdown("done")
		end)
	end)
end)
