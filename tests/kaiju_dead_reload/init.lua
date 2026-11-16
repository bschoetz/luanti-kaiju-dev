-- A kaiju killed shortly before the server stops (saved during its die clip) must be gone
-- after the restart, not come back as a dead body that can't be killed. run.sh starts this
-- scenario twice on the same world (the file "restart"). Start 1 spawns the four kaiju,
-- kills them and shuts down 1 s later; start 2 counts the kaiju. Good: "RESULT ok".
local T = kaiju_test
local KAIJU = {"gojira:gojira", "mothra:mothra", "ghidorah:ghidorah", "cthulhu:cthulhu"}
local storage = core.get_mod_storage()

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	local start = storage:get_int("start") + 1
	storage:set_int("start", start)
	core.after(2, function()
		player:set_pos(vector.new(0, 9.5, -20))
		if start == 1 then
			core.after(2, function()
				local objs = {}
				for i, name in ipairs(KAIJU) do objs[i] = core.add_entity(vector.new(i * 12 - 30, 8.6, 10), name) end
				core.after(3, function()
					local dead = 0
					for _, o in ipairs(objs) do
						local e = o:get_luaentity()
						if e then
							e.health = 0
							e:check_for_death({type = "generic"}, 1)
							if e.dead then dead = dead + 1 end
						end
					end
					T.log("start 1: killed " .. dead .. " of " .. #KAIJU)
					core.after(1, core.request_shutdown, "done")
				end)
			end)
		else
			core.after(4, function()
				local left = {}
				for _, e in pairs(core.luaentities) do
					for _, name in ipairs(KAIJU) do
						if e.name == name then left[#left + 1] = name .. (e.dead and "(dead)" or "") end
					end
				end
				T.result({left = #left, which = table.concat(left, ",")}, {"left", "which"}, {{"left", {0, 0}}})
				core.after(1, core.request_shutdown, "done")
			end)
		end
	end)
end)
