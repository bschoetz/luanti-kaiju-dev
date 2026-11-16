-- Photo scenario for the README of the published modpack: posed puppets (no AI) of the four
-- kaiju on a plains beach (mapgen v7, seed 7), noon, HUD and chat off, 1280x720.
--   tests/run.sh readme_shots 40
-- Five scenes of SCENE_TIME seconds, each logged as "SCENE <n> <label>" when it is set up;
-- screenshots belong to a scene by file time against the log time in client.log.
-- tools/publish.sh runs this and picks the last frame of each scene. Gojira's breath and
-- Ghidorah's beams are particles drawn here in the style of the mobs' own.
local T = kaiju_test
local L = T.log

local function register(name, size, glow)
	core.register_entity("readme_shots:" .. name, {
		initial_properties = {
			visual = "mesh", mesh = name .. ".glb", textures = {name .. ".png"}, glow = glow,
			visual_size = {x = size, y = size}, physical = false, static_save = false,
			collisionbox = {-1, 0, -1, 1, 2, 1}, backface_culling = false,
		},
	})
end
-- sizes and glow as in the mobs' definitions
register("gojira", 7.5, 0)
register("mothra", 8, 4)
register("ghidorah", 7.5, 0)
register("cthulhu", 6, 5)

local UNIT = 0.75 -- nodes per model unit for Gojira and Ghidorah (SCALE / 10)
local objs, spawners = {}, {}

-- yaw that faces from a towards b (entities and the camera face +Z at yaw 0)
local function yaw_to(a, b) return core.dir_to_yaw(vector.subtract(b, a)) end

local function puppet(name, pos, yaw, frames, fps)
	local o = core.add_entity(pos, "readme_shots:" .. name)
	o:set_yaw(yaw)
	o:set_animation(frames, fps or 1, 0, true) -- once per scene (tests/README.md, puppets)
	objs[#objs + 1] = o
	return o
end

-- a point of a puppet's model, as kaiju_core.model_point: forward, side (+ = his right), up
local function model_point(o, fwd, side, up)
	local yaw = o:get_yaw()
	local f, s = core.yaw_to_dir(yaw), core.yaw_to_dir(yaw - math.pi / 2)
	return vector.offset(o:get_pos(), f.x * fwd + s.x * side, up, f.z * fwd + s.z * side)
end

-- A jet of particles from `from` to `to` for `time` seconds (Gojira's breath, a beam).
local function jet(from, to, time, def)
	local dist = vector.distance(from, to)
	local v = vector.multiply(vector.direction(from, to), dist / def.exptime)
	spawners[#spawners + 1] = core.add_particlespawner({
		amount = def.rate * time, time = time,
		pos = {min = vector.offset(from, -0.3, -0.3, -0.3), max = vector.offset(from, 0.3, 0.3, 0.3)},
		vel = {min = vector.offset(v, -def.spread, -def.spread, -def.spread), max = vector.offset(v, def.spread, def.spread, def.spread)},
		exptime = def.exptime, size = def.size, glow = 14, texture = def.texture,
	})
end
local function breath(g, to, time)
	-- mouth in the breath pose (gojira/init.lua MOUTH_FORWARD / MOUTH_HEIGHT)
	jet(model_point(g, 8.42 * UNIT, 0, 13.86 * UNIT), to, time, {rate = 160, exptime = 1.0, spread = 2,
		size = {min = 5, max = 9}, texture = {name = "fire_basic_flame.png", alpha_tween = {1, 0.3}, scale_tween = {1, 2.5}}})
end
local function beams(gh, to, time)
	-- head joints in the reared pose + mouth length (ghidorah/init.lua HEAD_JOINT, MOUTH_LEN)
	for _, j in ipairs({{8.24, -0.06, 20.24, 5.8}, {6.97, 5.96, 19.56, 5.0}, {6.90, -6.04, 19.54, 5.0}}) do
		local joint = model_point(gh, j[1] * UNIT, j[2] * UNIT, j[3] * UNIT)
		local from = vector.add(joint, vector.multiply(vector.direction(joint, to), j[4] * UNIT))
		local dest = vector.offset(to, j[2] * 0.2, 0, 0)
		-- standing sparks along the line: a moving jet arrives in clumps at the client's frame rate
		local n = math.ceil(vector.distance(from, dest) / 0.8)
		for k = 0, n do
			local p = vector.add(from, vector.multiply(vector.subtract(dest, from), k / n))
			spawners[#spawners + 1] = core.add_particlespawner({
				amount = 30 * time, time = time,
				pos = {min = vector.offset(p, -0.3, -0.3, -0.3), max = vector.offset(p, 0.3, 0.3, 0.3)},
				exptime = 0.3, size = {min = 2.5, max = 4.5}, glow = 14,
				texture = "mcl_particles_crit.png^[colorize:#ffe14a:200",
			})
		end
	end
end

local function clear()
	for _, o in ipairs(objs) do o:remove() end
	for _, id in ipairs(spawners) do core.delete_particlespawner(id) end
	objs, spawners = {}, {}
end

-- Hide every HUD element (the games add their own: hearts, hunger, XP) and the chat, which
-- would show the client's own errors (Mineclonia's missing poplar texture).
local function hide_hud(player)
	player:hud_set_flags({hotbar = false, healthbar = false, crosshair = false, wielditem = false,
		breathbar = false, minimap = false, minimap_radar = false, basic_debug = false, chat = false})
	for id in pairs(player:hud_get_all()) do player:hud_remove(id) end
end

local function camera(player, pos, target, fov)
	local d = vector.subtract(target, pos)
	player:set_pos(vector.offset(pos, 0, -1.625, 0)) -- pos is the eye
	player:set_look_horizontal(core.dir_to_yaw(d))
	player:set_look_vertical(-math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z)))
	player:set_fov(fov or 72)
end

local function ground(x, z) return vector.new(x, T.column(x, z) + 0.5, z) end
local function at(x, z, y) local p = ground(x, z); if y then p.y = y end; return p end

-- A plains beach that slopes gently into the ocean to the west (mapgen v7, seed 7).
local S = vector.new(-1664, 0, 80)
local SCENE_TIME = 6
local scenes = {
	{"hero: all four", function(player)
		local cam = vector.new(S.x - 76, 7, S.z)
		local ct = puppet("cthulhu", ground(S.x - 42, S.z + 3), 0, {x = 330, y = 330})
		local go = puppet("gojira", ground(S.x - 6, S.z + 28), 0, {x = 30, y = 30})
		local gh = puppet("ghidorah", ground(S.x - 2, S.z - 26), 0, {x = 265, y = 265})
		local mo = puppet("mothra", vector.new(S.x - 22, 32, S.z + 2), 0, {x = 59, y = 59})
		for _, o in ipairs({ct, go, gh, mo}) do o:set_yaw(yaw_to(o:get_pos(), cam)) end
		go:set_yaw(go:get_yaw() + 0.5); gh:set_yaw(gh:get_yaw() - 0.4); mo:set_yaw(mo:get_yaw() + 0.3)
		camera(player, cam, vector.new(S.x - 14, 15, S.z), 62)
	end},
	{"gojira breathing fire", function(player)
		local go = puppet("gojira", ground(S.x + 8, S.z), math.pi / 2, {x = 172, y = 172})
		breath(go, ground(S.x - 16, S.z - 2), SCENE_TIME)
		camera(player, vector.new(S.x - 8, 7, S.z + 30), vector.new(S.x - 2, 9, S.z), 68)
	end},
	{"mothra in flight", function(player)
		local mo = puppet("mothra", vector.new(S.x - 26, 22, S.z - 6), 0, {x = 59, y = 59})
		local cam = vector.new(S.x - 2, 6, S.z + 16)
		mo:set_yaw(yaw_to(mo:get_pos(), cam) + 0.7)
		camera(player, cam, vector.offset(mo:get_pos(), 0, -3, 0), 62)
	end},
	{"ghidorah firing beams", function(player)
		local gh = puppet("ghidorah", ground(S.x + 10, S.z + 4), 0, {x = 265, y = 265})
		local cam = vector.new(S.x - 26, 9, S.z - 18)
		local to = ground(S.x - 22, S.z + 14)
		gh:set_yaw((yaw_to(gh:get_pos(), cam) + yaw_to(gh:get_pos(), to)) / 2) -- between camera and target
		beams(gh, to, SCENE_TIME)
		camera(player, cam, vector.offset(gh:get_pos(), -6, 10, 0), 68)
	end},
	{"cthulhu rising from the sea", function(player)
		local ct = puppet("cthulhu", ground(S.x - 38, S.z + 4), 0, {x = 330, y = 330})
		local cam = vector.new(S.x - 14, 5, S.z + 10)
		ct:set_yaw(yaw_to(ct:get_pos(), cam))
		camera(player, cam, vector.offset(ct:get_pos(), 0, 8, 0), 60)
	end},
}

core.register_on_joinplayer(function(player)
	core.set_timeofday(0.5)
	player:set_physics_override({gravity = 0, speed = 0, jump = 0})
	player:set_clouds({density = 0.15, thickness = 4})
	player:set_pos(vector.offset(S, -30, 20, 0))
	hide_hud(player)
	core.after(2, function()
		core.emerge_area(vector.new(S.x - 130, -40, S.z - 130), vector.new(S.x + 130, 60, S.z + 130), function(_, _, left)
			if left > 0 then return end
			local fl = {}
			for d = -60, 20, 4 do fl[#fl + 1] = d .. ":" .. T.column(S.x + d, S.z) end
			L("ground along x: " .. table.concat(fl, " "))
			-- the first scene once unlogged, so the client has the map blocks (and their light)
			scenes[1][2](player)
			for i, scene in ipairs(scenes) do
				core.after(i * SCENE_TIME, function()
					clear()
					core.set_timeofday(0.5)
					hide_hud(player)
					L("SCENE " .. i .. " " .. scene[1])
					scene[2](player)
				end)
			end
			core.after((#scenes + 1) * SCENE_TIME, function() core.request_shutdown("done") end)
		end)
	end)
end)
