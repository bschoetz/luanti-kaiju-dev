-- Visual check of the Cthulhu model: own puppet entities (no AI), every
-- animation from the front, the side and three-quarter view, a size comparison and the bone
-- overrides the mob code uses or may use. Logs only the scene labels; use screenshots:
--   tests/run.sh cthulhu_show 40      (about 1.6-1.8 s per screenshot; 40 cover all 16 scenes)
-- The mesh and texture come from the cthulhu mod (kaiju/cthulhu/).
-- Layout: three puppets per scene at z = 28, (left to right) facing the viewer, from the
-- side and three-quarter. A HUD line names the scene. _l (+X) is the mob's own right; seen
-- from the front it is on the viewer's left.
-- Good: stance feet planted in walk; the wing hooks above the head in every upright pose;
-- wings spread only in roar; die ends lying face down on the ground. Scenes 12-14 (relative
-- rotation on "head"): x+ pitches the nose down, y+ rolls the +X side down, z+ turns the
-- nose towards +X; the same signs as ghidorah's head_X. Scene 15: x- swings the feelers
-- forward. Scene 16: the magenta marker sits between the claws of claws_r (hold pose 290:
-- in front of the face).
local function L(s) core.log("action", "[test] " .. s) end

local function register(name, mesh, texture, size)
	core.register_entity("cthulhu_show:" .. name, {
		initial_properties = {
			visual = "mesh", mesh = mesh, textures = {texture},
			visual_size = {x = size, y = size}, physical = false, static_save = false,
			collisionbox = {-1, 0, -1, 1, 2, 1}, backface_culling = false,
		},
	})
end
register("puppet", "cthulhu.glb", "cthulhu.png", 6)
register("gojira", "gojira.glb", "gojira.png", 7.5)
register("ghidorah", "ghidorah.glb", "ghidorah.png", 7.5)
core.register_entity("cthulhu_show:marker", {
	initial_properties = {
		visual = "cube", textures = {"[fill:1x1:#ff00ff"}, visual_size = {x = 0.15, y = 0.15, z = 0.15},
		physical = false, pointable = false, static_save = false, glow = 14,
	},
})

local GROUND = 8.5
local FRONT, SIDE, QUARTER, BACK = math.pi, math.pi / 2, math.pi * 0.8, 0
local puppets = {}
local function puppet(x, z, yaw, range, fps, loop, y, name)
	local o = core.add_entity({x = x, y = GROUND + (y or 0), z = z}, "cthulhu_show:" .. (name or "puppet"))
	o:set_yaw(yaw)
	o:set_animation(range, fps, 0, loop ~= false)   -- once per scene, see tests/README.md
	puppets[#puppets + 1] = o
	return o
end
local function three(range, fps, loop, y)
	return puppet(-17, 28, FRONT, range, fps, loop, y), puppet(0, 28, SIDE, range, fps, loop, y),
		puppet(17, 28, QUARTER, range, fps, loop, y)
end
local function frozen(frame) return three({x = frame, y = frame}, 1) end
local function rot_all(objs, bones, v)
	for _, o in ipairs(objs) do
		for _, b in ipairs(bones) do o:set_bone_override(b, {rotation = {vec = v, absolute = false}}) end
	end
end
local FEELER_ROOTS = {}
for k = 1, 8 do FEELER_ROOTS[k] = "feeler" .. k .. "a" end

-- {label, function}; one scene every SCENE_TIME seconds
local SCENE_TIME = 3
local scenes = {
	{"stand 0-60 @15: front / side / three-quarter", function() three({x = 0, y = 60}, 15) end},
	{"walk 70-110 @20", function() three({x = 70, y = 110}, 20) end},
	{"swim 120-160 @16 (4 nodes up)", function() three({x = 120, y = 160}, 16, true, 4) end},
	{"rise 170-230 @20, looped", function() three({x = 170, y = 230}, 20) end},
	{"punch (claw swipe) 240-260, slow motion @8", function() three({x = 240, y = 260}, 8) end},
	{"grab 270-300 @10 (slow), _r arm", function() three({x = 270, y = 300}, 10) end},
	{"roar 310-350 @20 (madness roar, wings spread)", function() three({x = 310, y = 350}, 20) end},
	{"die 360-400 @14, non-looping", function() three({x = 360, y = 400}, 14, false) end},
	{"dormant 410-450 @8 (the idol pose)", function() three({x = 410, y = 450}, 8) end},
	{"size: gojira / cthulhu / ghidorah", function()
		puppet(-22, 36, QUARTER, {x = 0, y = 60}, 15, true, 0.1, "gojira")
		puppet(0, 30, FRONT, {x = 0, y = 60}, 15)
		puppet(22, 38, QUARTER, {x = 0, y = 60}, 15, true, 0, "ghidorah")
	end},
	{"from behind: stand / roar hold (frame 330) / dormant", function()
		puppet(-17, 28, BACK, {x = 0, y = 60}, 15)
		puppet(0, 28, BACK, {x = 330, y = 330}, 1)
		puppet(17, 28, BACK + 0.6, {x = 410, y = 450}, 8)
	end},
	-- head only, frozen neutral pose
	{"override head rotation x=+0.6 rad (relative)", function() rot_all({frozen(0)}, {"head"}, {x = 0.6, y = 0, z = 0}) end},
	{"override head rotation y=+0.6 rad (relative)", function() rot_all({frozen(0)}, {"head"}, {x = 0, y = 0.6, z = 0}) end},
	{"override head rotation z=+0.6 rad (relative)", function() rot_all({frozen(0)}, {"head"}, {x = 0, y = 0, z = 0.6}) end},
	{"override all feelerNa: x=-0.9 / y=+0.6 / feeler3a only x=-1.4", function()
		local a, b, c = frozen(0)
		a:set_yaw(SIDE) c:set_yaw(SIDE)
		rot_all({a}, FEELER_ROOTS, {x = -0.9, y = 0, z = 0})
		rot_all({b}, FEELER_ROOTS, {x = 0, y = 0.6, z = 0})
		rot_all({c}, {"feeler3a"}, {x = -1.4, y = 0, z = 0})
	end},
	{"grip marker on claws_r: grab close (282) / hold (290) / stand", function()
		local objs = {puppet(-17, 28, SIDE, {x = 282, y = 282}, 1), puppet(0, 28, QUARTER, {x = 290, y = 290}, 1),
			puppet(17, 28, QUARTER, {x = 0, y = 60}, 15)}
		for _, o in ipairs(objs) do
			local m = core.add_entity(o:get_pos(), "cthulhu_show:marker")
			-- bone-local offset in mesh units, Luanti axes (x, y up, z forward); see README-model.md
			m:set_attach(o, "claws_r", {x = 0, y = -1.2, z = 1.9}, {x = 0, y = 0, z = 0})
			puppets[#puppets + 1] = m
		end
	end},
}

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	player:hud_set_flags({hotbar = false, healthbar = false, crosshair = false, wielditem = false, breathbar = false})
	local hud = player:hud_add({type = "text", position = {x = 0.5, y = 0.04}, text = "", number = 0xFFFFFF, size = {x = 2, y = 2}})
	core.after(2, function()
		local air, list = {}, {}
		for x = -45, 45 do for z = 2, 60 do for y = 9, 24 do air[#air + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(air, {name = "air"})   -- the savanna trees stand in the way
		for x = -1, 1 do for z = -1, 1 do for y = 9, 13 do list[#list + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(list, {name = "mcl_core:cobble"})
		player:set_pos({x = 0, y = 14, z = 0}); player:set_look_horizontal(0); player:set_look_vertical(0.1)
		for i, scene in ipairs(scenes) do
			core.after(2 + (i - 1) * SCENE_TIME, function()
				for _, o in ipairs(puppets) do o:remove() end
				puppets = {}
				player:hud_change(hud, "text", i .. ": " .. scene[1])
				L("SCENE " .. i .. " " .. scene[1])
				scene[2]()
			end)
		end
		core.after(2 + #scenes * SCENE_TIME, function() core.request_shutdown("done") end)
	end)
end)
