-- Ghidorah's beams against a player, small mobs on the line, and the box of a stump.
-- A Ghidorah pinned 20 nodes from a pinned survival player (HP topped up every step, the
-- HP lost per volley summed):
--   bare    all three heads, no armour: 1 per head and tick, dealt once per tick (about 24
--           a volley; it was 3 per head: 72).
--   cow     the side heads severed, a cow held on the centre head's line: the beam hurts
--           the cow and goes on to the player (it used to stop at the first mob).
--           The left stump's hit box is at the neck joint, not where the skull was.
--   iron    all heads again, full iron armour: the volley still hurts (on VoxeLibre armour
--           rounds each hit to whole HP: 1 per head would round to 0).
-- Good: "RESULT ok".
local T = kaiju_test
local PLAYER, KPOS = vector.new(0, 8.5, 20), vector.new(0, 8.6, 0)
local lost = 0
core.register_on_player_hpchange(function(_, change) if change < 0 then lost = lost - change end end, false)

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	core.after(4, function()
		local k = core.add_entity(KPOS, "ghidorah:ghidorah")
		local ke = k:get_luaentity()
		local phase, beaming, cow, cow_hurt, done = "bare", false, nil, 0, false
		local r = {}
		local function finish()
			if done then return end
			done = true
			T.result(r, {"bare", "cow_hurt", "behind_cow", "stump_off", "iron"},
				{{"bare", {16, 30}}, {"cow_hurt", {6, 100}}, {"behind_cow", {3, 12}}, {"stump_off", {0, 0.5}}, {"iron", {4, 30}}})
			core.request_shutdown("done")
		end
		core.after(50, finish)
		-- the centre head's joint in the "beam" pose (kaiju/ghidorah/init.lua HEAD_JOINT, x 0.75)
		local function cow_pos()
			local joint = kaiju_core.model_point(ke, 8.24 * 0.75, -0.06 * 0.75, 20.24 * 0.75)
			local mid = vector.multiply(vector.add(joint, vector.offset(player:get_pos(), 0, 0.9, 0)), 0.5)
			return vector.offset(mid, 0, -0.7, 0)
		end
		local function volley_over()
			T.log(("%s: lost %.1f"):format(phase, lost))
			if phase == "bare" then
				r.bare, phase = lost, "cow"
				ke._regrow_time = 12 -- (off for the cow volley, back for the iron one)
				mcl_util.deal_damage(ke._hitbox_l, 500, {type = "mob"})
				mcl_util.deal_damage(ke._hitbox_r, 500, {type = "mob"})
				cow = core.add_entity(cow_pos(), "mobs_mc:cow")
				core.after(1, function()
					-- the left joint in the stand and the beam pose: the box is at one of them
					local box, off = ke._hitbox_l:get_pos(), 100
					for _, j in ipairs({{3.59, 6.09, 21.89}, {6.97, 5.96, 19.56}}) do
						off = math.min(off, vector.distance(box, kaiju_core.model_point(ke, j[1] * 0.75, j[2] * 0.75, j[3] * 0.75)))
					end
					r.stump_off = off
				end)
			elseif phase == "cow" then
				r.behind_cow, r.cow_hurt, phase = lost, cow_hurt, "iron"
				cow:remove()
				cow = nil
				for _, n in ipairs({"helmet", "chestplate", "leggings", "boots"}) do
					mcl_armor.equip(ItemStack("mcl_armor:" .. n .. "_iron"), player)
				end
			else
				r.iron = lost
				finish()
			end
			lost = 0
		end
		core.register_globalstep(function()
			if done or not k:is_valid() then return end
			player:set_pos(PLAYER)
			if player:get_hp() > 0 then player:set_hp(20) end
			k:set_pos(KPOS)
			ke.health = 600
			if cow and cow:is_valid() then
				local ce = cow:get_luaentity()
				cow:set_pos(cow_pos())
				cow:set_velocity(vector.zero())
				cow_hurt, ce.health = cow_hurt + math.max(10 - ce.health, 0), 10
			end
			local b = ke._beam_time ~= nil
			if beaming and not b then volley_over() end
			beaming = b
		end)
	end)
end)
