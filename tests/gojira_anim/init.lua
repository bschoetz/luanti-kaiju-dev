local def = core.registered_entities["gojira:gojira"]
local walk_fps_per_node = def.animation.walk_speed
local function L(s) core.log("action", "[test] " .. s) end
L(("walk_speed=%.2f"):format(walk_fps_per_node))

-- puppet: same mesh, scripted motion, no AI
local function puppet(pos, yaw, anim, fps, vel)
	local o = core.add_entity(pos, "gojira:gojira")
	local e = o:get_luaentity()
	o:set_animation(anim, fps, 0, true)
	e.on_step = function(self)
		self.object:set_velocity(vel or vector.zero())
		self.object:set_yaw(yaw)
	end
	return o
end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	player:set_pos({x = 0, y = 9, z = 0})
	player:set_look_horizontal(0); player:set_look_vertical(-0.3)
	local hud = player:hud_add({type = "text", position = {x = 0.5, y = 0.12}, text = "", number = 0xFFFFFF, size = {x = 2, y = 2}})
	local function label(t) player:hud_change(hud, "text", t); L("SCENE " .. t) end
	local p
	core.after(2, function()
		label("Szene 1: Laufen (Seitenansicht)")
		local v = 4.5
		p = puppet({x = -28, y = 8.6, z = 38}, -math.pi / 2, {x = 70, y = 110}, walk_fps_per_node * v, {x = v, y = 0, z = 0})
	end)
	core.after(14, function()
		p:remove()
		label("Szene 2: Stehen")
		p = puppet({x = 4, y = 8.6, z = 24}, math.pi * 0.75, {x = 0, y = 60}, 15)
	end)
	core.after(19, function() label("Szene 3: Feueratem"); p:set_animation({x = 150, y = 200}, 20, 0, true) end)
	core.after(25, function() label("Szene 4: Biss"); p:set_animation({x = 120, y = 140}, 12, 0, true) end)
	core.after(30, function() label("Szene 5: Sterben"); p:set_animation({x = 210, y = 240}, 10, 0, false) end)
	core.after(35, function()
		p:remove()
		label("Szene 6: echte KI, Verfolgung")
		local g = core.add_entity({x = 0, y = 8.6, z = 45}, "gojira:gojira")
		local last = g:get_pos()
		for t = 1, 12 do
			core.after(t, function()
				if not g:get_pos() then return end
				local pos = g:get_pos()
				local _, fps = g:get_animation()
				local e = g:get_luaentity()
				L(("ai t=%d moved=%.2f n/s vel=%.2f anim=%s fps=%.1f breath=%s"):format(t, vector.distance(vector.new(pos.x, 0, pos.z), vector.new(last.x, 0, last.z)), e:get_velocity(), tostring(e._current_animation), fps, tostring(e._breath_time ~= nil)))
				last = pos
				player:set_hp(20)
			end)
		end
	end)
	core.after(49, function() core.request_shutdown("done") end)
end)
