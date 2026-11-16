-- Pathfinder for the kaiju on VoxeLibre (loaded by vl.lua; Mineclonia has its own). An A*
-- over a height field: one cell per node column, in a window around the mob. A cell's
-- height is the highest ground under the whole body standing there, so a path keeps the
-- body clear of walls, trunks and leaves. The same decisions as Mineclonia's pathfinder
-- gives the kaiju: a full path, else a partial one to the cell nearest the goal, else none
-- (then kaiju_core's stuck detection and bulldozer take over). README.md §7 has the rules.
--
-- Limits: goals beyond the window are reached by chaining partial paths; a wall longer
-- than about 40 nodes can't be walked around (no way within the window: bulldoze). Caves
-- and overhangs lower than the body are walls; unloaded columns are solid. A search out
-- of time returns the best partial path so far.

local RADIUS = 24           -- window: cells this far from the start, each way
local BAND_DOWN = 16        -- ground is looked for down to this far below the feet
local MAX_EXPANSIONS = 1200
local MAX_US = 4000         -- per plan, checked every 8 expansions (the limit in practice: 100-150 cells)
local STEP_UP = 1.125       -- Mineclonia's GWP_JUMP_HEIGHT
local SAFE_DROP = 3         -- without a target (Mineclonia's _safe_fall_distance); attacking: any drop
local HEURISTIC = 1.5       -- weight of the octile distance (Mineclonia's)
local SQRT2 = math.sqrt(2)
local W = 2 * RADIUS + 1
local floor, abs, max, min = math.floor, math.abs, math.max, math.min

-- unloaded -> CONTENT_IGNORE, which like unknown nodes counts as solid
local raw = core.get_node_raw or function(x, y, z)
	return core.get_content_id(core.get_node({x = x, y = y, z = z}).name)
end

local AIR, WALK, WATER, LAVA = 0, 1, 2, 3
local class = {} -- content id -> one of the above (missing: WALK)
core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_nodes) do
		local g = def.groups or {}
		class[core.get_content_id(name)] = name ~= "ignore" and (def.walkable and WALK
			or (g.lava or 0) > 0 and LAVA or (g.water or 0) > 0 and WATER or AIR) or nil
	end
end)

-- (us: microseconds spent planning)
local stats = {plans = 0, partial = 0, failed = 0, max_us = 0, total_us = 0}
kaiju_core._vl_nav_stats = stats

local NEIGHBOURS = {{1, 0, 1}, {-1, 0, 1}, {0, 1, 1}, {0, -1, 1},
	{1, 1, SQRT2}, {1, -1, SQRT2}, {-1, 1, SQRT2}, {-1, -1, SQRT2}}

-- A path for the mob from where it stands towards `target`: a list of positions (cell
-- centres at standing height) with the next one last, as Mineclonia's `waypoints`, and
-- whether it is partial (ends short of the target). nil: no cell nearer than the start.
function kaiju_core.vl_find_path(self, target)
	local t0 = core.get_us_time()
	local pos, cb = self.object:get_pos(), self.collisionbox
	local feet = pos.y + cb[2]
	local sx, sz = floor(pos.x + 0.5), floor(pos.z + 0.5)
	local gx, gz = floor(target.x + 0.5), floor(target.z + 0.5)
	-- The nodes the body covers standing on a cell centre (as kaiju_core.smash), which give
	-- the cell its height, and those it can touch anywhere in the cell: it walks up to half
	-- a node beside the line of cell centres (corners, a new plan in mid-stride), so these
	-- must be free of walls too. Gojira (4.8 wide): 5 x 5 and 7 x 7; the others 7 x 7 twice.
	local lo, hi = floor(cb[1] + 0.5), floor(cb[4] + 0.5)
	local wide_lo, wide_hi = floor(cb[1]), math.ceil(cb[4])
	-- Up to where smash clears (its roof is not ground), down to BAND_DOWN below the feet.
	local top, bottom = floor(feet + cb[5] + 1.5), floor(feet + 0.5) - BAND_DOWN
	local swim_depth = self._swim_depth or math.huge
	local water_cost = self.gwp_penalties.WATER or 8
	local max_drop = self.attack and math.huge or SAFE_DROP

	-- Columns: standing height (false: none, or lava), water above the ground, swimming.
	local pad = max(-wide_lo, wide_hi)
	local cw = W + 2 * pad
	local col_h, col_wet, col_swim = {}, {}, {}
	local function column(x, z)
		local i = (x - sx + RADIUS + pad) * cw + z - sz + RADIUS + pad
		local h = col_h[i]
		if h ~= nil then return h end
		local surface
		h = false
		for y = top, bottom, -1 do
			local c = class[raw(x, y, z)] or WALK
			if c == WALK then
				h = y + 0.5
				break
			elseif c == LAVA then
				surface = nil
				break
			elseif c == WATER then
				surface = surface or y + 0.5
				if surface - y > swim_depth then break end -- (deep enough to swim: the floor doesn't matter)
			end
		end
		-- deep water: it swims with its feet swim_depth below the surface (kaiju_core.check_standin)
		if surface and swim_depth < math.huge and (not h or surface - h >= swim_depth) then
			h = surface - swim_depth
			col_swim[i] = true
		end
		col_h[i], col_wet[i] = h, surface ~= nil
		return h
	end

	-- The highest column of x, z + from .. z + to (false: one has no standing height),
	-- kept in `cache`: the cells beside share these rows.
	local function row(cache, x, z, from, to)
		local i = (x - sx + RADIUS + pad) * cw + z - sz + RADIUS + pad
		local s = cache[i]
		if s ~= nil then return s end
		s = -math.huge
		for dz = from, to do
			local h = column(x, z + dz)
			if not h then
				s = false
				break
			end
			if h > s then s = h end
		end
		cache[i] = s
		return s
	end

	-- Cells: the highest column under the body (false: impassable), and whether it swims
	-- there (the centre column is deep water and nothing under the body is higher).
	-- Impassable too with a column in the wider box that it could not step onto: a wall.
	local rows, wide_rows = {}, {}
	local cell_h, cell_swim = {}, {}
	local function cell(x, z, j)
		local s = cell_h[j]
		if s ~= nil then return s end
		s = -math.huge
		local wide = s
		for dx = wide_lo, wide_hi do
			local h = row(wide_rows, x + dx, z, wide_lo, wide_hi)
			local own = h and dx >= lo and dx <= hi and row(rows, x + dx, z, lo, hi)
			if not h then
				cell_h[j] = false
				return false
			end
			if h > wide then wide = h end
			if own and own > s then s = own end
		end
		local i = (x - sx + RADIUS + pad) * cw + z - sz + RADIUS + pad
		if wide > s + STEP_UP or (col_wet[i] and water_cost < 0) then s = false end
		cell_swim[j] = s and col_swim[i] and s == col_h[i] or false
		cell_h[j] = s
		return s
	end

	local start = RADIUS * W + RADIUS
	-- The start: the cell's height if it stands there (within a step of it: on stairs the
	-- cell's highest column is ahead of its feet) or is in mid-air above it; sunk below
	-- (in deep water, in a pit) it starts from where its feet are.
	local s0 = cell(sx, sz, start)
	cell_h[start] = s0 and feet >= s0 - STEP_UP and s0 or feet
	cell_swim[start] = false

	-- May it move from height `from` into the cell (x, z)?
	local function enter(from, x, z, j)
		local s = cell(x, z, j)
		if not s then return false end
		return (s - from <= STEP_UP or cell_swim[j]) and from - s <= max_drop
	end

	local function estimate(x, z)
		local dx, dz = abs(x - gx), abs(z - gz)
		return (max(dx, dz) + (SQRT2 - 1) * min(dx, dz)) * HEURISTIC
	end

	-- open set: a binary heap of (f, cell); a cell may be in it several times
	local heap_f, heap_j, n = {estimate(sx, sz)}, {start}, 1
	local g, parent, closed = {[start] = 0}, {}, {}
	local best, best_h = start, estimate(sx, sz)
	local goal = abs(gx - sx) <= RADIUS and abs(gz - sz) <= RADIUS and (gx - sx + RADIUS) * W + gz - sz + RADIUS
	local start_h = best_h
	local found = false
	local expansions = 0
	while n > 0 do
		-- pop
		local j = heap_j[1]
		local lf, lj = heap_f[n], heap_j[n]
		heap_f[n], heap_j[n] = nil, nil
		n = n - 1
		if n > 0 then
			local i = 1
			while true do
				local c = 2 * i
				if c > n then break end
				if c < n and heap_f[c + 1] < heap_f[c] then c = c + 1 end
				if heap_f[c] >= lf then break end
				heap_f[i], heap_j[i] = heap_f[c], heap_j[c]
				i = c
			end
			heap_f[i], heap_j[i] = lf, lj
		end
		if not closed[j] then
			closed[j] = true
			local x, z = floor(j / W) - RADIUS + sx, j % W - RADIUS + sz
			local h = estimate(x, z)
			if h < best_h then best, best_h = j, h end
			if j == goal then
				found = true
				break
			end
			-- a goal beyond the window: the way there leaves the window here
			if not goal and h < start_h and (abs(x - sx) == RADIUS or abs(z - sz) == RADIUS) then
				best = j
				break
			end
			expansions = expansions + 1
			if expansions >= MAX_EXPANSIONS or (expansions % 8 == 0 and core.get_us_time() - t0 > MAX_US) then break end
			local s, gj = cell_h[j], g[j]
			for _, d in ipairs(NEIGHBOURS) do
				local dx, dz = d[1], d[2]
				local nx, nz = x + dx, z + dz
				if abs(nx - sx) <= RADIUS and abs(nz - sz) <= RADIUS then
					local nj = j + dx * W + dz
					-- (diagonally the body also passes over both neighbours beside the line)
					if not closed[nj] and enter(s, nx, nz, nj)
							and (dx == 0 or dz == 0 or (enter(s, nx, z, j + dx * W) and enter(s, x, nz, j + dz))) then
						local ng = gj + d[3]
							+ (col_wet[(nx - sx + RADIUS + pad) * cw + nz - sz + RADIUS + pad] and water_cost or 0)
						if not g[nj] or ng < g[nj] then
							g[nj], parent[nj] = ng, j
							-- push
							local f = ng + estimate(nx, nz)
							n = n + 1
							local i = n
							while i > 1 do
								local p = floor(i / 2)
								if heap_f[p] <= f then break end
								heap_f[i], heap_j[i] = heap_f[p], heap_j[p]
								i = p
							end
							heap_f[i], heap_j[i] = f, nj
						end
					end
				end
			end
		end
	end

	-- back from the end, keeping the cells where the direction changes
	local path = (best ~= start or found) and {} or nil -- (found at the start: an empty path)
	local j, out_x, out_z = best, nil, nil
	while path and parent[j] do
		local p = parent[j]
		local x, z = floor(j / W) - RADIUS, j % W - RADIUS
		local dx, dz = x - (floor(p / W) - RADIUS), z - (p % W - RADIUS)
		if dx ~= out_x or dz ~= out_z then
			path[#path + 1] = vector.new(x + sx, cell_h[j], z + sz)
		end
		out_x, out_z = dx, dz
		j = p
	end

	local us = core.get_us_time() - t0
	stats.plans = stats.plans + 1
	stats.total_us = stats.total_us + us
	stats.max_us = max(stats.max_us, us)
	if not path then
		stats.failed = stats.failed + 1
	elseif not found then
		stats.partial = stats.partial + 1
	end
	return path, not found
end
