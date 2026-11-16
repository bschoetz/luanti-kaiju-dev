-- Navigation course (tests/README.md §Navigation courses): block smashing is ON, but the
-- wall between Gojira and the player (cobble, 3 high, 41 long, a 7-wide gap off the direct
-- line) is protected, so he can't break it.
-- Good: RESULT ok. He walks through the gap to the player; the wall is untouched.
local T = kaiju_test
local W1, W2 = vector.new(-20, 9, 0), vector.new(20, 11, 0)
local is_protected = core.is_protected
function core.is_protected(p, name)
	if p.z == 0 and p.y >= 9 and p.y <= 11 and p.x >= -20 and p.x <= 20 then return true end
	return is_protected(p, name)
end
T.nav_course({
	area = {vector.new(-30, 0, -24), vector.new(30, 0, 26)},
	build = function()
		T.fill(W1, W2, "mcl_core:cobble")
		T.fill(vector.new(4, 9, 0), vector.new(10, 11, 0), "air")
	end,
	mob = "gojira:gojira", spawn = vector.new(0, 8.6, 14), player = vector.new(0, 9, -12), time = 60,
	setup = function(e) e._breath_cooldown = 1e9 end,
	blocks = {{"mcl_core:cobble", W1, W2}},
	keys = {"reached", "removed", "max_y", "moved", "nav_max_us"},
	expect = {{"reached", {0, 60}}, {"removed", {0, 0}}},
})
