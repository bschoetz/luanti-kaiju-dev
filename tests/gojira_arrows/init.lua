-- Arrows at Gojira's upper body: his position is at his feet and the server's raycast only
-- finds objects within 5 nodes of the arrow's path, so chest and head carry hit boxes
-- (kaiju_core.ensure_hitboxes) that pass the damage on to him.
-- Good: "control" leaves his HP unchanged (no hit boxes: the arrow flies through him),
-- "chest" and "head" each take HP off.
-- a full draw: Mineclonia takes a factor, VoxeLibre the speed (its bow's maximum)
local POWER = kaiju_core.voxelibre and 40 or 1.0
local function L(s) core.log("action", "[test] " .. s) end

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(2, function()
		player:set_pos({x = 0, y = 9, z = -30})
		core.after(2, function()
			local g = core.add_entity({x = 0, y = 8.6, z = 10}, "gojira:gojira")
			local e = g:get_luaentity()
			local function shoot(label, aim)
				local eye = vector.offset(player:get_pos(), 0, 1.6, 0)
				local hp = e.health
				mcl_bows.shoot_arrow("mcl_bows:arrow", eye, vector.direction(eye, aim), 0, player, POWER, 10)
				core.after(1.5, function()
					L(("%s: arrow at %s (%.1f above his feet) -> hp %d -> %d"):format(label,
						core.pos_to_string(vector.round(aim)), aim.y - g:get_pos().y, hp, e.health))
				end)
			end
			-- control: the same shot without hit boxes
			core.after(1, function()
				local ensure = kaiju_core.ensure_hitboxes
				kaiju_core.ensure_hitboxes = function() end
				local aim = e._hitbox_chest:get_pos()
				e._hitbox_chest:remove(); e._hitbox_head:remove()
				shoot("control", aim)
				core.after(1.6, function() kaiju_core.ensure_hitboxes = ensure end)
			end)
			core.after(4, function() shoot("chest", e._hitbox_chest:get_pos()) end)
			core.after(6, function() shoot("head", e._hitbox_head:get_pos()) end)
		end)
	end)
	core.after(13, function() core.request_shutdown("done") end)
end)
