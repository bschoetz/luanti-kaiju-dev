-- Visual check of the King Ghidorah model: own puppet entities (no dependency on
-- ghidorah's Lua), every animation from the front, the side and three-quarter view.
-- Logs only the scene labels; use screenshots: tests/run.sh ghidorah_show 66
-- Layout: three puppets per scene, seen (left to right) three-quarter, from the side, from
-- the front. A HUD line names the scene. _l (+X, straight horns) is the mob's own right.
-- Good: stance feet planted in walk; wings up AND down in fly/hover; die ends lying on the
-- ground; scenes 12-14 show what a relative head_c rotation override does per axis
-- (x+ nose down, y+ roll, z+ nose towards the _l side); scene 15 shows the side heads' jaws
-- opened by an override; scene 16 shows red neck stumps.
local function L(s) core.log("action", "[test] " .. s) end

local function register(name, mesh, texture)
	core.register_entity("ghidorah_show:" .. name, {
		initial_properties = {
			visual = "mesh", mesh = mesh, textures = {texture},
			visual_size = {x = 7.5, y = 7.5}, physical = false, static_save = false,
			collisionbox = {-1, 0, -1, 1, 2, 1}, backface_culling = false,
		},
	})
end
register("puppet", "ghidorah.glb", "ghidorah.png")
register("gojira", "gojira.glb", "gojira.png")

local GROUND = 8.5
local FRONT, SIDE, QUARTER, BACK = math.pi, math.pi / 2, math.pi * 0.8, math.pi * 0.2
local puppets = {}
local function puppet(x, z, yaw, range, fps, loop, y, name)
	local o = core.add_entity({x = x, y = GROUND + (y or 0), z = z}, "ghidorah_show:" .. (name or "puppet"))
	o:set_yaw(yaw)
	o:set_animation(range, fps, 0, loop ~= false)   -- once per scene, see tests/README.md
	puppets[#puppets + 1] = o
	return o
end
local function three(range, fps, loop, y)
	return puppet(-30, 46, FRONT, range, fps, loop, y), puppet(0, 46, SIDE, range, fps, loop, y),
		puppet(30, 46, QUARTER, range, fps, loop, y)
end
local function override(o, rot, scale)
	for _, b in ipairs({"head_c", "head_l", "head_r"}) do
		o:set_bone_override(b, {rotation = rot and {vec = rot, absolute = false}, scale = scale and {vec = scale, absolute = false}})
	end
end

local function override_scene(rot)
	for _, o in ipairs({three({x = 240, y = 240}, 1)}) do
		o:set_bone_override("head_c", {rotation = {vec = rot, absolute = false}})
	end
end

-- {label, function}; one scene every SCENE_TIME seconds
local SCENE_TIME = 3
local scenes = {
	{"stand 0-60 @15: front / side / three-quarter", function() three({x = 0, y = 60}, 15) end},
	{"walk 70-110 @20", function() three({x = 70, y = 110}, 20) end},
	{"fly 120-150 @24 (10 nodes up)", function() three({x = 120, y = 150}, 24, true, 10) end},
	{"hover 160-200 @20 (10 nodes up)", function() three({x = 160, y = 200}, 20, true, 10) end},
	{"bite 210-230, slow motion @7", function() three({x = 210, y = 230}, 7) end},
	{"beam 240-290 @20, non-looping (holds the last frame)", function() three({x = 240, y = 284}, 20, false) end},
	{"takeoff 300-320 @7 (slow)", function() three({x = 300, y = 320}, 7) end},
	{"land 330-350 @7 (slow)", function() three({x = 330, y = 350}, 7) end},
	{"die 360-400 @14, non-looping", function() three({x = 360, y = 400}, 14, false) end},
	{"beam_fly 410-450 @20 (10 nodes up)", function() three({x = 410, y = 450}, 20, true, 10) end},
	{"size: gojira / ghidorah from behind / ghidorah wings spread (beam hold)", function()
		puppet(-30, 46, QUARTER, {x = 0, y = 60}, 15, true, 0.1, "gojira")
		puppet(0, 46, BACK, {x = 0, y = 60}, 15)
		puppet(30, 46, FRONT, {x = 260, y = 260}, 1)
	end},
	-- head_c only, frozen neutral pose
	{"override head_c rotation x=+0.6 rad (relative)", function() override_scene({x = 0.6, y = 0, z = 0}) end},
	{"override head_c rotation y=+0.6 rad (relative)", function() override_scene({x = 0, y = 0.6, z = 0}) end},
	{"override head_c rotation z=+0.6 rad (relative)", function() override_scene({x = 0, y = 0, z = 0.6}) end},
	{"override jaw_l + jaw_r rotation x=+0.7 rad (side heads beaming on their own)", function()
		for _, o in ipairs({three({x = 0, y = 60}, 15)}) do
			for _, b in ipairs({"jaw_l", "jaw_r"}) do
				o:set_bone_override(b, {rotation = {vec = {x = 0.7, y = 0, z = 0}, absolute = false}})
			end
		end
	end},
	{"severed heads (scale 0): head_r / head_c / all three", function()
		local a, b, c = three({x = 0, y = 60}, 15)
		a:set_yaw(QUARTER) b:set_yaw(QUARTER)
		a:set_bone_override("head_r", {scale = {vec = vector.zero()}})
		b:set_bone_override("head_c", {scale = {vec = vector.zero()}})
		override(c, nil, vector.zero())
	end},
}

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	player:hud_set_flags({hotbar = false, healthbar = false, crosshair = false, wielditem = false, breathbar = false})
	local hud = player:hud_add({type = "text", position = {x = 0.5, y = 0.04}, text = "", number = 0xFFFFFF, size = {x = 2, y = 2}})
	core.after(2, function()
		local list = {}
		for x = -1, 1 do for z = -1, 1 do for y = 9, 22 do list[#list + 1] = vector.new(x, y, z) end end end
		core.bulk_set_node(list, {name = "mcl_core:cobble"})
		player:set_pos({x = 0, y = 23, z = 0}); player:set_look_horizontal(0); player:set_look_vertical(0.05)
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
