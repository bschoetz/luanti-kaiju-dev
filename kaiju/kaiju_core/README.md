# Kaiju Core

A library mod with the mechanics that the giant mobs of the `kaiju` modpack
([`../README.md`](../README.md)) share, on top of
[Mineclonia](https://codeberg.org/mineclonia/mineclonia)'s `mcl_mobs`. It defines
the global table `kaiju_core` and registers one invisible helper entity,
`kaiju_core:hitbox` (§3.9); no mob, no item, no node. On VoxeLibre it also provides the
part of Mineclonia's mob API the kaiju use (§7, `vl.lua`).

| Part | Functions | Used by |
|---|---|---|
| Node classification | `is_immune`, `is_terrain` | `smash` |
| Settings | `griefing_enabled` (a modpack setting on top of `mobs_griefing`) | `smash_step`, gojira, ghidorah |
| Smashing through the world | `smash`, `smash_step` (body box, floor layer, foot-level terrain, containers, falling nodes, dust, optional tail sweep) | gojira, ghidorah, cthulhu |
| Bulldozer and melee standoff | `update_bulldoze`, `gopath`, `end_bulldoze`, `standoff_gap` | gojira, ghidorah, cthulhu (on land; `standoff_gap` also when he swims) |
| Water | `check_standin` (wade vs. swim by depth) | gojira, ghidorah, cthulhu (always wades; his own sea mode swims) |
| Knockback | `no_knockback(def)` | gojira, mothra, ghidorah, cthulhu |
| Death | `check_for_death` (plays "die", stops the mob) | gojira, ghidorah, cthulhu |
| Flight | `ground_y`, `keep_clearance`, `fly_velocity`, `death_fall` | mothra, ghidorah; cthulhu steers with `fly_velocity` under water, staying physical |
| Hit boxes | `ensure_hitboxes` (entity `kaiju_core:hitbox`) | gojira, ghidorah, cthulhu |
| Truce after a Ghidorah's death | `start_truce`, `retreat_goal`, `get_active_target`, table `truce` | ghidorah (start), gojira, mothra |
| Game support (§7) | `mcl_mobs` (the mob API to use), `voxelibre`, `mob_griefing`, `tile_drops` | all |
| Small shared helpers (§3.12) | `model_point`, `flat_dist`, `is_kaiju`, `cthulhu_rule`, `lock_animations`, `play`, `is_water`, `is_solid`, `water_column` | all |

Ghidorah walks **and** flies and uses both halves (§5.3). Cthulhu
([`../cthulhu/README.md`](../cthulhu/README.md)) uses the ground half on land and
`fly_velocity` in deep water; he takes no part in the truce.

This document is for developers. It describes what the code does. Where a code comment
says something different, the code is documented and the difference is flagged with
**Note:**.

| File | Role |
|---|---|
| `kaiju/kaiju_core/init.lua` | The whole library |
| `kaiju/kaiju_core/vl.lua` | VoxeLibre only: the compatibility layer (§7) |
| `kaiju/kaiju_core/mod.conf` | Mod metadata and dependencies |
| `kaiju/settingtypes.txt` | The modpack's settings, read through `griefing_enabled` (§3.7) |

History (`git log`): `69bb353` moved this code out of `gojira/init.lua` and
`mothra/init.lua` unchanged in behaviour (all `tests/` scenarios gave the same numbers).
Since then the mods moved into the `kaiju/` modpack folder; paths in older commits have no
`kaiju/` prefix.
The design reasoning and the test results behind each mechanic are in
[`gojira/README.md`](../gojira/README.md), [`mothra/README.md`](../mothra/README.md) and
[`ghidorah/README.md`](../ghidorah/README.md). The test scenarios are described in
[`tests/README.md`](../../tests/README.md).

Mineclonia framework references point to
`vendor/mineclonia/mods/ENTITIES/mcl_mobs/<file>` (vendor checkout `994845e`, git-ignored).

---

## 1. Dependencies and installation

`mod.conf`: `depends = mcl_mobs, mobs_mc, mcl_init, mcl_util`, `min_minetest_version = 5.10`.

| Dependency | Used for |
|---|---|
| `mcl_mobs` | `mcl_mobs.mob_class` (base `gopath`, `check_standin`), mob methods such as `cancel_navigation`, `go_to_stupidly` |
| `mobs_mc` | `mobs_mc.is_mob_griefing_enabled(mob_name)` (Mineclonia) |
| `mcl_init` | `mcl_vars.do_tile_drops` (the doTileDrops gamerule, Mineclonia) |
| `mcl_util` | `mcl_util.deal_damage` (hit boxes pass projectile damage on) |

All four ship with Mineclonia and with VoxeLibre. A kaiju mod lists `kaiju_core` in its own `depends`, so
`kaiju_core` must be enabled in the world next to the kaiju. It ships in the `kaiju`
modpack, and enabling the modpack enables it: see [`../README.md`](../README.md) for
installing and upgrading. `tests/run.sh` links the whole modpack into every test world.

---

## 2. Conventions

- Every function except `is_immune`, `is_terrain`, `griefing_enabled`, `ground_y`,
  `no_knockback` and `start_truce` takes the
  mob's luaentity as `self` (an `mcl_mobs` mob). Call them as `kaiju_core.f(self, ...)`, not
  with `:`.
- State lives in plain `self._*` fields, listed per function below. The names are the
  ones gojira and mothra used before the move (`_smash_timer`, `_bulldoze_time`,
  `_floor`, ...). Don't reuse these names for something else in a kaiju.
- `mcl_mobs` serializes every non-function field into staticdata (`api.lua`), so
  all these fields survive an unload/reload (a running bulldoze resumes, `_goal` and
  `_floor` are restored).
- Units: nodes (n), seconds (s), radians, model units (u) only in the tail table.

---

## 3. API

### 3.1 Node classification

#### `kaiju_core.is_immune(name) -> bool`

True for nodes a kaiju never breaks:

- `"air"` and `"ignore"`;
- unknown nodes (no definition) and every node with `walkable == false` (plants, liquids,
  fire, torches, rails, ...);
- `_mcl_blast_resistance >= 1200` (obsidian, bedrock, anvil, ...);
- any group in `IMMUNE_GROUPS = {unbreakable, indestructible, end_portal_frame, command_block, fire}`.

#### `kaiju_core.is_terrain(name) -> bool`

True if the node is in any of `TERRAIN_GROUPS = {overworld_carvable, dirt, sand,
hardened_clay, soil, grass_block, material_sand}`, the groups Mineclonia's cave carver
treats as ground. `smash` keeps such nodes at foot level so a walking kaiju climbs hills
instead of tunnelling through them.

`is_terrain` returns false for unknown node names.

### 3.2 Smashing

#### Config: `self._smash`

Put the config on the mob definition (it is then shared by all instances):

```lua
mob._smash = {
	lookahead = 3,          -- nodes the box is stretched in the facing direction (default 3)
	tail = {                -- optional; omit for a mob without a tail
		segments = { {d, h, w, plate[, side]}, ... },  -- model units, see below
		unit = SCALE / 10,  -- nodes per model unit
		first = 3,          -- first segment to sweep (default 1)
	},
}
```

Each tail segment is `{distance behind the mob's position, centre height above its feet,
thickness, plate height on top[, side offset]}`, all in model units; `unit` converts them
to nodes. With the optional fifth value the segment is swept **twice**, that far to the
left and to the right of the centre line: two splayed tails. Gojira's segments have four
values, Ghidorah's five.

#### `kaiju_core.smash_step(self, dtime, mob_name)`

Call it every step from `ai_step`, after `mob_class.ai_step`.

- Returns at once if `self.dead` or
  `kaiju_core.griefing_enabled(mob_name, "kaiju_smash_blocks")` is false (§3.7): the
  setting `kaiju_smash_blocks` is off, or Mineclonia forbids griefing for this mob
  (gamerule `mobs_griefing`, or the per-mob list `mcl_mobs_griefing_disable_individual`).
  `mob_name` is the entity name, e.g. `"gojira:gojira"`.
- Runs `smash(self, self._smash or {})` every `SMASH_INTERVAL` (0.25 s), throttled while
  idle:
  - **Idle** means no `self.attack`, horizontal speed² < 0.01, and yaw unchanged
    (< 0.01 rad) since the last interval.
  - `_smash_idle` counts consecutive idle intervals; `smash` runs only when
    `_smash_idle % SMASH_IDLE_TICKS == 0`. Any non-idle interval resets it to 0 and
    smashes at once. While idle it smashes every 8 × 0.25 = 2 s, which still catches a
    wall it paced into.
  - With a target the mob is never idle: an obstacle that stops it dead must go at once.

| Reads | Writes |
|---|---|
| `self.dead`, `self.attack`, `self._smash`, object velocity and yaw | `_smash_timer`, `_smash_yaw`, `_smash_idle` |

#### `kaiju_core.smash(self, cfg)`

One smash pass, without timer or griefing check (`smash_step` does those; a caller of
`smash` checks `griefing_enabled` itself, as Ghidorah does before clearing his landing spot). Reads
`self.collisionbox`, `self.floats`, the object's position and yaw; `cfg` is the table above.

1. **Box.** The collision box, stretched `cfg.lookahead` nodes towards the facing
   direction (`yaw_to_dir`, per axis, only on the side it faces). Vertically from
   `p1.y = round(pos.y + cb[2] − 0.5)` (the layer it stands on) to
   `round(pos.y + cb[5] + 1)` (one above the head: headroom for stepping up).
2. **Floor and terrain.**
   - On land (`self.floats ~= 1`): `floor_y = p1.y`. That layer is not dug whatever it is
     made of, except nodes that need a real dig (below). Natural terrain is kept up to
     `keep_terrain_to = p1.y + 1`, the foot layer.
   - Swimming (`self.floats == 1`): `floor_y = nil` and `keep_terrain_to = p1.y`. A
     swimmer can't step up a steep shore, so it cuts through its foot layer instead.
3. Every node in the box goes through `smash_node` (below), then the tail sweep runs if
   `cfg.tail` is set.
4. **Falling nodes.** For each (x, z) column, `core.check_for_falling` runs on the highest
   removed node, so sand and gravel resting on top fall.
5. **FX.** One particle spawner over the bounding box of everything removed
   (`amount = min(8·n, 96)`, 0.3 s, node texture of a random victim), and one `dug` sound
   of a random victim (gain 2, heard within 48 nodes). Nothing happens if nothing was
   removed.

`smash_node(p, floor_y, keep_terrain_to, removed, column_tops)` (local). A
node is **skipped** if any rule matches, in this order:

| Rule | Skip if |
|---|---|
| Immune | `is_immune(name)` |
| Terrain at foot level | `p.y <= keep_terrain_to` and `is_terrain(name)` |
| Protection | `core.is_protected(p, "")` (empty player name: protected areas are never touched) |
| Floor layer | `p.y == floor_y` and the node needs no real dig |

Removal:

- **Real dig** when the node has `after_dig_node` or `groups.container > 0`:
  `core.dig_node(p)` without a digger. Chests and furnaces drop their contents
  (Mineclonia does it in `after_dig_node`), doors and beds lose both halves, and the
  node's own drop goes through `core.handle_node_drops`, which honours doTileDrops. The
  node counts as removed only if `dig_node` returns true.
  The call is wrapped in `pcall`: some dig callbacks assume a player digger and raise an
  error (`mcl_beehives` indexes the digger's inventory in creative mode, which crashed a
  real world). On an error the node counts as removed if it is no longer there (the drops
  have happened by then), and a warning
  `[kaiju_core] dig callback of <node> failed: <error>` is logged once per node name
  (`warned_dig`). Scenario `kaiju_dig_callbacks`.
- **Fast path** otherwise: `core.remove_node(p)`. With `DROP_CHANCE` (5 %), and only if
  `mcl_vars.do_tile_drops` is on, it also drops `core.get_node_drops(node, "")` (marked
  `shortcut:` in the code), so a rampage doesn't flood the world with items.
  `on_destruct` still runs; `after_dig_node` does not.

**Tail sweep** (`sweep_tail`, local, lines 117-150). The server doesn't know the animated
pose, so the tail is a fixed line of boxes straight behind the mob, swept for every yaw it
passed through since the last pass. Walking straight it trails through the path the body
already cleared, so only turning costs anything.

- `diff` is the wrapped yaw change since `self._tail_yaw` (written every pass). Below
  0.03 rad nothing happens.
- The change is split into `steps = min(ceil(|diff| / TAIL_YAW_STEP), TAIL_MAX_STEPS)`
  samples.
- For each sample and each segment `first..#segments`, with `d, h, w, plate` converted to
  nodes, it smashes a square column centred `d` behind the mob (with a side offset: two
  columns, `side` to the right and to the left of that point):
  - half-width `r = max(w/2, TAIL_SEG_HALF·unit) + 0.5`
  - vertical range `pos.y + h − w/2 .. pos.y + h + w/2 + plate`
- It uses the same `smash_node` rules as the body. A `seen` set (keyed by
  `core.hash_node_position`) de-duplicates the overlapping samples.

| Reads | Writes |
|---|---|
| `self.collisionbox`, `self.floats`, object position and yaw, `cfg` | `_tail_yaw` (only with `cfg.tail`) |

### 3.3 Bulldozer

The A* pathfinder rarely finds room for a huge body in forests or towns. If the mob hasn't
closed in on its target for `STUCK_TIME`, it walks straight at it for `BULLDOZE_TIME` and
`smash` clears the way. Wire up all three functions:

#### `kaiju_core.update_bulldoze(self, dtime, attach_pos, target_pos)`

Call from `attack_melee` before the base method.

- **Standoff first:** if the mob is at standoff distance from its target (see below) and
  still navigating, it calls `cancel_navigation()` and `halt_in_tracks()`.
- The stuck detection below is the local `stuck(self, dtime, dist, near)`, which a truce
  retreat uses as well (§3.10).
- While `_bulldoze_time` is set it only counts it down. At ≤ 0 it clears it and calls
  `self:cancel_navigation()`, so normal pathfinding resumes at the next `gopath`.
- Otherwise it measures progress as the **horizontal** distance from `attach_pos` to
  `target_pos`. `_best_dist` is the best distance so far, `_stuck_timer` the time since it
  last improved by more than 1 node. The timer resets when the distance is within
  `self.reach + 1`, on the first measurement, or on a gain of more than 1 node.
- After `STUCK_TIME` (3 s) without progress: `_bulldoze_time = BULLDOZE_TIME` (6 s),
  `cancel_navigation()`, `go_to_stupidly(target_pos, self.pursuit_bonus)`.

#### `kaiju_core.gopath(self, target, speed_bonus, ...) -> bool`

Call from the mob's `gopath` override. At standoff distance (see below) it does nothing
and returns `true`, so base `attack_melee` starts no new walk. While `_bulldoze_time` is
set, or while the mob is inside the standoff gap but its bite does not reach (a target above
the ground, see below), every `gopath` call
(from base `attack_melee` and from `check_pace`) cancels navigation, calls
`go_to_stupidly(target, speed_bonus)` with the fresh position and returns `true` ("path
found", so base `attack_melee` doesn't add its failure delay). Otherwise it calls
`mob_class.gopath`.

#### `kaiju_core.end_bulldoze(self)`

Call from `attack_end`. Clears `_best_dist` and `_stuck_timer`, so the next target starts
its own stuck detection. If a bulldoze is running it clears `_bulldoze_time` and calls
`cancel_navigation()` (drops the straight-line `stupid_target`). Without that, roaming
would stay straight-line and the next target would inherit the remaining time.

| Reads | Writes |
|---|---|
| `self.reach`, `self.pursuit_bonus` | `_bulldoze_time`, `_stuck_timer`, `_best_dist` |

The bulldoze timer only advances while `update_bulldoze` is called. A mob that skips it
during another action (Gojira's fire breath) pauses the bulldoze for that time.

#### Melee standoff (`at_standoff`)

mcl_mobs' `attack_melee` walks a mob to its target's **own position**. For ordinary mobs
the stock pushing (`mob_class:collision`) keeps the bodies apart, but that force is far
too weak for a kaiju walking at 6 n/s, and it only acts between two mobs that are both
`pushable`. Ghidorah was not, so nothing at all kept him and Gojira apart: both walked to
the other's feet and stood inside each other (`kaiju_clinch` measured 0.4 nodes between
their centres for the whole fight).

`at_standoff(self)` is true when the horizontal distance to `self.attack` is below

    min(own half-width + target's half-width + STANDOFF, self.reach − 0.5)

(half-width = `collisionbox[4]`, `STANDOFF` = 2 nodes; this gap is
`kaiju_core.standoff_gap(self, tcb)`, with `tcb` the target's collision box, and Cthulhu's
sea mode stops at the same distance), and the target is at body height:
its feet below the mob's top and the mob's feet below the target's top. Under a flying
Mothra or a player on a tower the mob walks on as before. While it is true,
`update_bulldoze` stops the walk and `gopath` refuses to start one, so the mob stands and
bites from where it is. The `min` with the reach keeps the target biteable.

The gap is horizontal, but mcl_mobs measures the bite in 3D (feet to feet). So the
standoff also needs `vector.distance(own pos, target pos) <= self.reach`. A target inside
the gap but above the ground (a swimmer over deep water, a player on a roof at chest
height) would otherwise be out of reach for good, and for Gojira too close for his fire
breath: he stood still, and the stuck detection never fired, because he was "close". In
that case `at_standoff` returns `false, true`, and `gopath` walks straight on towards the
target (`go_to_stupidly`: the pathfinder has no node to go to in mid-air) until the bite
reaches. `gojira_overhead` has a player hovering 5.8 nodes above his feet: he used to stop
at 4.4 nodes (7.3 in 3D, reach 7) and never bit; now he bites from the second he arrives.
A target 7 to 9 nodes straight above his feet is still out of both reach and breath range;
that was so before the standoff existed.

- Gojira (half-width 2.4, reach 7) and Ghidorah (2.6, reach 8) stop at 6.5 and 7 nodes and
  need about a node to come to rest: `kaiju_clinch` shows 5.5-6.4 between their centres;
  the collision boxes touch at 5.0.
- Against a player Gojira stops 4.7 nodes away instead of standing on him.
- Bodies that are inside each other anyway (he landed on the other one) are pushed apart
  by the stock pushing. That needs both to be `pushable`, which is why Ghidorah no longer
  sets `pushable = false`. `kaiju_clinch` puts Gojira inside Ghidorah: they are apart
  again within half a second.
- `keep_clearance` (§3.6) has nothing to do with this: it keeps flyers above the terrain.
  The hit boxes (§3.9) are not mobs and are ignored by the pushing.

### 3.4 Water: `kaiju_core.check_standin(self, dtime, attach_pos, swim_depth)`

Call from the mob's `check_standin` override. Mineclonia switches any mob touching water
to swim physics (slow `water_velocity`) and lets `floats = 1` mobs bob on the surface.
For a giant that's wrong, so:

```lua
local depth, liquidtype = mob_class.check_standin(self, dtime, attach_pos)
if liquidtype == "water" then
	if depth < swim_depth then liquidtype = nil; self.floats = 0  -- wade: land physics
	else self.floats = 1 end                                      -- swim + buoyancy
end
return depth, liquidtype
```

- `depth` is the highest water surface above its feet anywhere in the collision box
  (`check_one_immersion_depth`, `physics.lua`). `swim_depth` is in nodes.
- Wading: the returned `nil` becomes `_last_liquidtype`, so `motion_step` uses land
  physics at full speed. Swimming: swim physics with the mob's `water_velocity`, and
  `floats = 1` makes `motion_step` jump on most steps while immersed, which holds it at
  about `swim_depth`.
- The base method has already applied environment damage with the **real** liquid type,
  so water still extinguishes the mob. Drowning is not handled here (Gojira overrides
  `step_drowning`).
- Writes `self.floats`, which `smash` reads (§3.2). Lava and other liquids pass through
  unchanged.

### 3.5 Knockback: `kaiju_core.no_knockback(def)`

Call on the mob **definition** before `register_mob`. Sets
`def.knockback_resistance = 1.0`, `def.knock_back = false` and
`def.projectile_knockback = function() end`.

Why: `mcl_util.calculate_knockback` returns `vector.zero()` for resistance 1.0, and
mcl_mobs **sets** that as the velocity, both in `mob_class:on_punch` (`combat.lua`,
gated by `self.knock_back`) and in `mob_class:projectile_knockback` (`combat.lua`,
called by bows, tridents and the wither). So with resistance 1.0 alone, every full punch
and every arrow stops the mob dead. Damage is applied before that block and is unchanged.

### 3.6 Flight

These assume a `physical = false` flyer that steers itself: no gravity, no node
collisions, altitude kept only by goal choice and `keep_clearance`. The mob writes
`self._goal` (a position) and optionally `self._goal_speed` (n/s) from its AI.

#### `kaiju_core.ground_y(pos) -> number`

A raycast from `pos + 2` down to `pos − 64` (`objects = false, liquids = true`). Returns
the top surface of the first node hit (`pointed.above.y − 0.5`), or `pos.y − 64` if none.
Water counts as ground, and so does anything pointable (leaves, plants). Start the ray
above the highest terrain you care about: callers pass a point 30 nodes above the
relevant height.

#### `kaiju_core.keep_clearance(self, self_pos, dtime, min_clearance)`

Call every AI step after the goal is set. Does nothing without `self._goal`.

- Every 0.25 s (`_floor_timer`), or when `_floor` is unset, it samples `ground_y` along
  the straight line from the mob to the goal: both ends plus a point every
  `CLEARANCE_STEP` (4) nodes, at most `CLEARANCE_SAMPLES` (12) steps, i.e. up to 13 rays.
  Longer paths get wider spacing. All rays start at `max(self_pos.y, goal.y) + 30`.
- `self._floor = highest ground + min_clearance`.
- Every call it clamps `self._goal.y = max(goal.y, _floor)` **in place**.

| Reads | Writes |
|---|---|
| `_goal` | `_goal.y`, `_floor`, `_floor_timer` |

#### `kaiju_core.fly_velocity(self, dtime, self_pos, default_speed) -> vector`

Call from `motion_step`. Sets the object's velocity and returns the wanted velocity
`want` (use it for facing).

- `speed = self._goal_speed or default_speed`.
- **Climb first:** while `self_pos.y < _floor − 2`, `want = (0, min(speed, 2·(_floor − y)), 0)`.
  It rises on the spot and only then crosses higher terrain. The same rule lifts a flyer
  spawned on the ground.
- Otherwise `want = (goal − pos) · min(speed, 2·dist) / dist`: full speed, slowing down
  linearly within `speed/2` nodes; `want = 0` within 0.5 nodes or without a goal.
- The velocity is blended towards `want` with `k = min(1, 1.5·dtime)`, a first-order lag
  with a time constant of about 0.67 s.

| Reads | Writes |
|---|---|
| `_goal`, `_goal_speed`, `_floor`, object velocity | object velocity |

#### `kaiju_core.death_fall(self, self_pos, fall_time)`

Call from `motion_step` while `self.dead` (mcl_mobs keeps calling `motion_step` for dead
mobs) and return. On the first call it sets `physical = true`, so the body lands on the
ground instead of falling through it, and picks a fall speed
`_falling = clamp(drop / (fall_time or DEATH_FALL_TIME), 8, DEATH_FALL_MAX)` with
`drop = y − ground_y(y)`. Every call it sets the velocity to `(0, −_falling, 0)`.

mcl_mobs removes the body `die frames / die_speed + DEATH_DELAY` after death
(`physics.lua`). For Mothra that is 30/10 + 0.5 = 3.5 s, so any drop up to 75 nodes
lands in about 2.5 s, and drops above 30 × 3.5 = 105 nodes are still removed in mid-air.
Pass a `fall_time` below your own die-clip length + 0.5 s if it differs from Mothra's.

| Reads | Writes |
|---|---|
| — | `_falling`, object `physical`, object velocity |

### 3.7 Settings: `kaiju_core.griefing_enabled(mob_name, setting) -> bool`

```lua
return core.settings:get_bool(setting, true) and kaiju_core.mob_griefing(mob_name)
```

One kind of block destruction is allowed if the modpack setting `setting` is on **and**
the game allows griefing for `mob_name` (`mob_griefing`: Mineclonia's
`mobs_mc.is_mob_griefing_enabled`, VoxeLibre's `mobs_griefing` setting). The setting is read on every call, so `/set`
and the settings menu take effect without a restart. An unset setting counts as on. The
settings are declared in `kaiju/settingtypes.txt`:

| Setting | Default | Checked in | Off means |
|---|---|---|---|
| `kaiju_smash_blocks` | true | `smash_step`; `ghidorah/init.lua` `touch_down` | no body smash, no tail sweep, no cleared landing spot |
| `kaiju_gojira_fire` | true | `gojira/init.lua`, `gojira:flame` `hit_node` | flames no longer place `mcl_fire:fire` (they still burn mobs and players) |
| `kaiju_ghidorah_beam_blasts` | true | `ghidorah/init.lua` `beam_tick` | beams no longer explode where they hit a node (they still hurt mobs and players) |

Scenario `kaiju_settings` runs all three off and then on.

### 3.8 Death: `kaiju_core.check_for_death(self, reason, damage)`

Assign it on the mob definition: `def.check_for_death = kaiju_core.check_for_death`
(Gojira and Ghidorah do; Mothra keeps the stock method). It wraps
`mob_class.check_for_death` and returns its result.

- **Before:** if `damage > 0` and `self.health <= 0` it clears
  `self._punch_animation_timeout`. While that timeout runs, mcl_mobs' `set_animation`
  turns every animation into `punch`, so a kaiju killed in mid-bite never played `die`.
- **After:** if the mob has just died (`self.dead` set by this call) it calls
  `self:halt_in_tracks(true)`. mcl_mobs lets a dying mob walk on, so a kaiju killed in
  mid-stride slid through its whole `die` clip.

| Reads | Writes |
|---|---|
| `self.health`, `self.dead` | `_punch_animation_timeout`, velocity (through `halt_in_tracks`) |

### 3.9 Hit boxes: `kaiju_core.ensure_hitboxes(self, parts)`

The server's raycast (which arrows use) only finds objects whose **position** is within
5 nodes of the ray, and a mob's position is at its feet. Arrows aimed at a kaiju's chest
or head flew through it. So the high parts carry an invisible object each, which passes
hits on to the kaiju. The code came from `ghidorah/init.lua` (`ghidorah:hitbox`) and is
unchanged in behaviour.

Call `ensure_hitboxes` every step of a living mob (`run_ai` or `ai_step`). It creates
the box of every part that has none (first step, after a reload, after a box was removed).

```lua
local HITBOXES = {
	{name = "chest", pos = function(self) return ... end, box = {-3, -3.5, -3, 3, 3.5, 3}},
	{name = "head", pos = function(self) return ... end},
}
kaiju_core.ensure_hitboxes(self, HITBOXES)
```

- `name`: the object is kept in `self._hitbox_<name>`. That is a top-level field on
  purpose: mcl_mobs drops ObjectRefs from staticdata only at the top level, inside a
  table they break saving.
- `pos(self)`: world position of the box centre, called every server step.
- `box`: selection box around that position, default `{-2, -2, -2, 2, 2, 2}`.

The entity `kaiju_core:hitbox`:

- a blank sprite, `physical = false`, `static_save = false` (never saved), armor group
  `immortal`, `_hittable_by_projectile = true` (for `mcl_bows`);
- `on_step` moves it to `pos(owner)` and removes it when the owner is gone or dead. It
  only calls `set_pos` when the position differs from the last one it set (`_pos` on the
  box): every `set_pos` is a packet to all clients, also for a kaiju that stands still;
- `on_punch` and `deal_damage` (called by `mcl_util.deal_damage`, i.e. projectiles) pass
  the hit on to the owner. During that call `owner._hit_part` is the part's name, so the
  owner's `receive_damage` can tell where it was hit (Ghidorah's heads); Gojira ignores it.

Projectiles of `mcl_mobs.register_arrow` (Gojira's flames) only hit mobs and players and
pass through hit boxes.

| Reads | Writes |
|---|---|
| `self.object`, `self.dead` (from the box) | `self._hitbox_<name>`, `self._hit_part` (during a hit) |

### 3.10 Truce after a Ghidorah's death

Mothra hunts Gojira when no Ghidorah is around, so the two allies used to turn on each
other over his body. Now they part: each species moves away as a group, in opposite
directions.

#### `kaiju_core.truce`

| Field | Default | Meaning |
|---|---|---|
| `radius` | 200 n | who takes part: loaded kaiju this close to the dead Ghidorah |
| `distance` | 150 n | how far each kaiju moves; the species end up 300 n further apart, beyond every view range |
| `timeout` | 180 s | a retreat ends after this, wherever the kaiju is |
| `arrive` | 4 n | horizontal distance to the goal that counts as arrived |

A table so that a test can shorten the walk (`tests/kaiju_truce` sets `distance = 40`).

#### `kaiju_core.start_truce(dead)`

Call with the ObjectRef of a Ghidorah that has just died (Ghidorah's `on_die`).

1. Collects the living `gojira:gojira` and `mothra:mothra` within `radius` of him. If
   another living `ghidorah:ghidorah` is in that radius, or one of the two species is
   missing, nothing happens.
2. Axis: the horizontal direction from the Mothras' centroid to the Gojiras' centroid
   (a random direction if they are less than half a node apart).
3. Every Gojira gets the goal *own position + distance · axis*, every Mothra *own
   position − distance · axis*. All members of a species get the same offset, so a group
   keeps its formation.

The state is plain numbers per kaiju, which mcl_mobs saves with the mob: `_retreat_x`,
`_retreat_z`, `_retreat_until` (game time in seconds) and `_retreat_attack_id` (see
below). A kaiju that is unloaded on the way goes on when it is loaded again, unless the
time has run out by then. `start_truce` also resets the stuck detection (`_best_dist`,
`_stuck_timer`).

#### `kaiju_core.retreat_goal(self, dtime) -> vector or nil`

The goal at the mob's own height while it retreats, else nil. The mob decides how to get
there: Gojira walks in a straight line (`go_to_stupidly`, with `smash_step` clearing the
way), Mothra flies at her cruise altitude. It ends the retreat (clears the fields and
calls `cancel_navigation`):

- on arrival and at `_retreat_until`;
- when the mob **was attacked** since the retreat started: mcl_mobs' `_last_attack_id`
  differs from `_retreat_attack_id`. Hits by a kaiju that is retreating as well don't
  count (a truce partner's gust or flame that was already under way), nor does damage
  without a source (poison, falling). The normal targeting rules then decide what
  happens: Gojira retaliates, Mothra hunts whatever she sees first;
- when a walker is **stuck**: pass the step's `dtime` (Gojira does, Mothra doesn't, as a
  flyer climbs on the spot in front of a wall). The same detection as the bulldozer's:
  no node closer to the goal for `STUCK_TIME`. That is Gojira in front of a cliff with
  `kaiju_smash_blocks` or `mobs_griefing` off; he used to push against it for the whole
  180 s.

#### `kaiju_core.get_active_target(self, self_pos)`

Assign it on the mob definition (`def.get_active_target = kaiju_core.get_active_target`).
While the mob retreats it returns nil instead of the target chosen by the targeting
rules, so `check_attack` ends a running attack (`attack_end`) and starts no new one: the
mob attacks nobody, neither the other kaiju nor players nor mobs. The exception is a
**living Ghidorah**: if the rules choose one (he is the first rule of both), the retreat
ends and he is the target.

`tests/kaiju_truce_end` runs the three early endings.

| Reads | Writes |
|---|---|
| position, `core.get_gametime()`, `_last_attack_id`, `_last_attacker`, `_active_target` | `_retreat_x`, `_retreat_z`, `_retreat_until`, `_retreat_attack_id`, `_best_dist`, `_stuck_timer`, navigation (when it ends) |

### 3.11 Model points: `kaiju_core.model_point(self, fwd, side, up) -> vector`

World position of a point given relative to the mob's feet and facing, in nodes: `fwd`
ahead, `side` to its right-hand side (model +X), `up` above the feet. Gojira's mouth and
hit boxes and Ghidorah's head joints (through his own wrapper, which takes model units)
use it. The server doesn't know the animated pose, so these are per-pose constants
turned by the yaw.

### 3.12 Small shared helpers

| Function | What it does | Used by |
|---|---|---|
| `kaiju_core.flat_dist(a, b) -> number` | Horizontal distance between two positions (only `x` and `z` are read). | `at_standoff`, `update_bulldoze`, `retreat_goal`, cthulhu |
| `kaiju_core.is_kaiju(ent) -> bool` | Is this luaentity (or nil) a Gojira, Mothra, Ghidorah or Cthulhu? | ghidorah (whom the side heads beam on their own; other Ghidorahs are excluded before), cthulhu (never grabbed) |
| `kaiju_core.cthulhu_rule() -> rule` | A new targeting rule: `build_nearest_target_rule("mob", {"cthulhu:cthulhu"}, nil, function() return 32 end, nil)`. The nearest Cthulhu in sight within 32 nodes, let go beyond 32 or after 3 s out of sight; never while he is under water without a target (his `valid_enemy`). The range must be a function: `build_nearest_target_rule` silently ignores a number. | gojira, ghidorah |
| `kaiju_core.lock_animations(def)` | Call on the mob definition before `register_mob`. Installs a `set_animation` that ignores every request except `"die"` while `self._anim_lock` is above 0. mcl_mobs sets walk, stand and punch on its own every step on the ground; this keeps a one-shot clip running. The mob counts `_anim_lock` down in its own step (`if self._anim_lock then self._anim_lock = self._anim_lock - dtime end`). | ghidorah, cthulhu |
| `kaiju_core.play(self, anim, time)` | Starts a one-shot clip and locks the animation for `time` seconds: clears the lock and `_punch_animation_timeout` (a punch that is still timing out would turn the clip into `"punch"`), calls `set_animation`, sets `_anim_lock`. | ghidorah (beam, takeoff, land), cthulhu (rise, roar, grab) |
| `kaiju_core.is_water(p) -> bool` | The node at `p` is in the `water` group. | cthulhu, `water_column` |
| `kaiju_core.is_solid(p) -> bool` | The node at `p` is walkable, or unknown or not loaded. | cthulhu, `water_column` |
| `kaiju_core.water_column(pos) -> floor_y, surface_y` | The column at `pos`: the top of the ground or sea floor, and of the water above it (`nil` if the floor is dry). It walks the nodes from `pos + 1`: up to 64 down to the first walkable node, or up to 40 up if `pos` is inside walkable nodes; then up through the water. | cthulhu (sea mode, home choice) |

`water_column` and `ground_y` (§3.6) answer different questions. `ground_y` is one raycast
from above and stops at the first pointable node: water, leaves and plants are its
"ground", which is what a flyer must clear. `water_column` costs up to 130 `get_node` calls
and tells the sea floor from the surface, whatever floats on the water (ice, lily pads).

Mothra's `set_anim` is a different lock (a locked clip can't be replaced by her own
calls either, and `set_animation` is not overridden), so she does not use
`lock_animations`.

---

## 4. Constants

All are `local` in `init.lua`; change them there (they affect every kaiju).

| Name | Value | Unit | Effect |
|---|---|---|---|
| `IMMUNE_GROUPS` | 5 groups | – | never smashed |
| blast-resistance cutoff | 1200 | `_mcl_blast_resistance` | never smashed at or above (hard-coded in `is_immune`) |
| `TERRAIN_GROUPS` | 7 groups | – | kept at foot level |
| `SMASH_INTERVAL` | 0.25 | s | smash rate. Keep `speed × interval < lookahead`. |
| `SMASH_IDLE_TICKS` | 8 | intervals | idle smash every 2 s |
| `DROP_CHANCE` | 0.05 | probability | random drops of fast-path removals |
| `warned_dig` | table | – | node names whose dig callback failed (one warning each per server run) |
| `TAIL_MAX_STEPS` | 6 | samples per pass | caps the cost of a fast turn |
| `TAIL_SEG_HALF` | 1.5 | model units (× `tail.unit`) | minimum half-length of a segment box |
| `TAIL_YAW_STEP` | 0.12 | rad | sample spacing (about 2 nodes at Gojira's tail tip) |
| tail threshold | 0.03 | rad per pass | smaller yaw changes don't sweep (hard-coded) |
| `STUCK_TIME` | 3.0 | s | no progress before bulldozing |
| `BULLDOZE_TIME` | 6.0 | s | straight-line duration |
| `STANDOFF` | 2.0 | n | gap kept between the bodies in melee (about one of it is used up stopping) |
| progress margin | 1 | n | gain needed to reset the stuck timer (hard-coded) |
| `CLEARANCE_STEP` | 4 | n | ground sample spacing along the path |
| `CLEARANCE_SAMPLES` | 12 | steps | cap on samples (13 rays per check) |
| clearance re-check | 0.25 | s | `_floor_timer` (hard-coded) |
| climb-first margin | 2 | n | below `_floor − 2` it only climbs (hard-coded) |
| steering lag | 1.5 | 1/s | `k = min(1, 1.5·dtime)` (hard-coded) |
| `DEATH_FALL_TIME` | 2.5 | s | the body falls fast enough to land within this |
| `DEATH_FALL_MAX` | 30 | n/s | fall speed cap (minimum 8, hard-coded) |
| ground ray | +2 / −64 | n | `ground_y` scan range |

---

## 5. Usage

### 5.1 Gojira (ground)

```lua
gojira._smash = {
	lookahead = 3,
	tail = {segments = TAIL, unit = UNIT, first = TAIL_FIRST},
}

function gojira:attack_melee(attach_pos, self_pos, dtime, target_pos, line_of_sight)
	-- ... fire breath returns early, which pauses the bulldoze timer ...
	kaiju_core.update_bulldoze(self, dtime, attach_pos, target_pos)
	return mob_class.attack_melee(self, attach_pos, self_pos, dtime, target_pos, line_of_sight)
end
function gojira:gopath(...) return kaiju_core.gopath(self, ...) end
function gojira:attack_end()
	self._breath_time = nil
	kaiju_core.end_bulldoze(self)
	return mob_class.attack_end(self)
end
function gojira:ai_step(dtime)
	mob_class.ai_step(self, dtime)
	if not self.dead then kaiju_core.ensure_hitboxes(self, HITBOXES) end  -- chest, head
	kaiju_core.smash_step(self, dtime, "gojira:gojira")
end
function gojira:check_standin(dtime, attach_pos)
	return kaiju_core.check_standin(self, dtime, attach_pos, SWIM_DEPTH)  -- 10
end
kaiju_core.no_knockback(gojira)
gojira.check_for_death = kaiju_core.check_for_death
mcl_mobs.register_mob("gojira:gojira", gojira)
```

### 5.2 Mothra (flight)

```lua
local ground_y = kaiju_core.ground_y  -- also used to pick wander goals

function mothra:motion_step(dtime, moveresult, self_pos)
	if self.dead then
		kaiju_core.death_fall(self, self_pos)
		return
	end
	local want = kaiju_core.fly_velocity(self, dtime, self_pos, WANDER_SPEED)
	-- face the enemy, or the horizontal part of `want`
end

function mothra:run_ai(dtime)
	local self_pos = self.object:get_pos()
	if self:check_attack(self_pos, dtime) then          -- attack_null sets _goal
		kaiju_core.keep_clearance(self, self_pos, dtime, MIN_CLEARANCE)  -- 10
		return
	end
	wander(self, self_pos, dtime)                        -- sets _goal, _goal_speed
	kaiju_core.keep_clearance(self, self_pos, dtime, MIN_CLEARANCE)
end
```

Mothra also calls `kaiju_core.no_knockback(mothra)` before `register_mob`.

### 5.3 A kaiju that walks and flies (Ghidorah)

The two halves assume different physics: the ground part relies on `physical = true`,
stock `motion_step` and the pathfinder; the flight part on `physical = false` and
`fly_velocity`. Keep one mode flag and switch everything with it. The sketch below shows
the pattern; the real code (`take_off`, `touch_down`, `choose_mode`, the landing descent)
is in `kaiju/ghidorah/init.lua` and described in
[`ghidorah/README.md`](../ghidorah/README.md):

```lua
local function set_flying(self, on)
	self._flying = on
	self.object:set_properties({physical = not on})
	self:cancel_navigation()
	self._floor = nil            -- resample the clearance floor on the next step
	if not on then self._goal = nil end
end

function ghidorah:motion_step(dtime, moveresult, self_pos)
	if not self._flying then
		return mob_class.motion_step(self, dtime, moveresult, self_pos)
	end
	if self.dead then return kaiju_core.death_fall(self, self_pos) end
	local want = kaiju_core.fly_velocity(self, dtime, self_pos, FLY_SPEED)
	-- facing from `want` or the target
end

function ghidorah:run_ai(dtime, moveresult)
	if not self._flying then
		return mob_class.run_ai(self, dtime, moveresult)   -- ai_functions, check_attack -> attack_melee
	end
	local self_pos = self.object:get_pos()
	-- own airborne AI: set self._goal / self._goal_speed, then
	kaiju_core.keep_clearance(self, self_pos, dtime, MIN_CLEARANCE)
end

function ghidorah:ai_step(dtime)
	mob_class.ai_step(self, dtime)
	if not self._flying then kaiju_core.smash_step(self, dtime, "ghidorah:ghidorah") end
end

function ghidorah:check_standin(dtime, attach_pos)
	return kaiju_core.check_standin(self, dtime, attach_pos, SWIM_DEPTH)
end
-- attack_melee / gopath / attack_end: as Gojira (update_bulldoze, gopath, end_bulldoze)
ghidorah._smash = {lookahead = 3, tail = {...}}
kaiju_core.no_knockback(ghidorah)
```

Points to decide (what Ghidorah does is in his README):

- **Smash only on foot.** `smash` treats any `floats ~= 1` mob as standing, so a flyer
  would keep the layer at its feet (and natural terrain up to one above) and dig
  everything else its box touches, such as tree tops it flies through. It would also pay
  for a full box of `get_node` calls per pass in open air, and the idle throttle only
  looks at horizontal speed, so a hovering flyer counts as idle. Skipping `smash_step` while airborne
  avoids all of that. `_tail_yaw` then goes stale, so the first pass after landing may
  sweep a large turn (capped at `TAIL_MAX_STEPS` samples).
- **Bulldozer on foot.** On take-off call `end_bulldoze(self)` so a running bulldoze and
  its straight-line target don't come back on landing.
- **Death.** `death_fall` is for flyers. On foot let the stock `motion_step` handle the
  body. Check that its die clip plus `DEATH_DELAY` is longer than `DEATH_FALL_TIME` (2.5 s),
  or it can vanish in mid-air (§6).
- **Landing.** `fly_velocity` never descends below the clearance floor, so a landing needs
  either a goal on the ground with clearance switched off (don't call `keep_clearance`
  during the descent) or a switch back to `physical = true` with stock gravity.
- **Water.** While flying `check_standin` still runs every step; over water it does
  nothing (no immersion). It only matters on foot.

---

## 6. Gotchas

"[code]" means verified by reading the code, "[test]" observed in a `tests/` scenario.

1. **The floor layer stays, except for containers** [code + test]. On land the layer the
   mob stands on is never removed, so it can't sink through sandstone, ice, the Nether or
   the End. Nodes that need a real dig (containers, anything with `after_dig_node` such as
   beds and doors) are the exception: after stepping up onto rubble or a natural-stone
   wall the mob walks a node higher, and a chest on the old floor would otherwise survive
   under its feet (`gojira_smash`).
2. **Containers need `dig_node`** [code]. `core.remove_node` silently deletes a chest's
   inventory, because Mineclonia drops contents in `after_dig_node`. `on_destruct` runs on
   both paths. Anything new that keeps state in `after_dig_node` goes through the real
   dig automatically.
3. **doTileDrops** [code]. Both the 5 % random drops and the drops of real digs
   (`handle_node_drops`) check the doTileDrops gamerule (`kaiju_core.tile_drops()`:
   `mcl_vars.do_tile_drops`; on VoxeLibre the `mcl_doTileDrops` setting). A chest's **contents** still drop
   with the gamerule off, only the chest item itself does not. No test covers the gamerule
   being off.
4. **Terrain groups decide what "hill" means** [code]. Only nodes in `TERRAIN_GROUPS` are
   kept at foot level. Natural stone is `overworld_carvable`; cobble, planks, bricks and
   most man-made blocks are not, so a kaiju walks through a 2-high wall but climbs a
   2-high dirt step. While swimming (`floats == 1`) the foot layer is cut too: leaving
   deep water, Gojira tunnels through the shore at swim depth (`gojira_water`).
5. **Protection uses an empty player name** [code]. `core.is_protected(p, "")` treats any
   protected area as off limits; there is no owner exception.
6. **The tail sweep has blind spots** [code]. `_tail_yaw` is updated before the 0.03 rad
   threshold check, so turns slower than 0.03 rad per 0.25 s (about 6.9°/s) never sweep.
   Turns faster than `TAIL_MAX_STEPS · TAIL_YAW_STEP` = 0.72 rad per pass are
   under-sampled (gaps at the tip). All samples use the current position, and the tail is
   always straight behind the mob in its rest pose. Two tails are two fixed lines (the
   side offset of §3.2), not a fan that follows the animation.
7. **Smash cost** [test]. Scales with the box volume (about 900 `get_node` calls per pass
   for Gojira) plus the tail sweep. `gojira_tail` measured 4 ms average and 112 ms worst
   case per pass. Several kaiju multiply it.
8. **The knockback zero-vector** [code + test]. `knockback_resistance = 1.0` alone makes
   every full punch and every arrow **set** the velocity to zero (§3.5). Use
   `no_knockback(def)`. `gojira_punch` shows the speed unchanged after punches, and 0.00
   with the stock path. All three kaiju call `no_knockback`.
9. **Path clearance samples a line** [code + test]. `keep_clearance` samples only the line
   under the mob's centre, every 4 nodes (wider on paths over 48 nodes). A spike 1-2 nodes
   wide between samples, or a tower beside the path under a wide wingspan, can be missed.
   Before path sampling, Mothra flew through a 36-high wall (`mothra_terrain`).
10. **Ceilings** [code, unverified in game]. `ground_y` is cast from 30 nodes above the
    path. Under a roof within that distance (caves, the Nether) it hits the roof, the
    floor jumps to roof + clearance, and climb-first drives the flyer up into the roof.
11. **Ground includes water and anything pointable** [code]. `liquids = true`, so lakes
    are ground (a flyer hovers above them). Leaves and plants are pointable, so trees raise
    the clearance floor.
12. **`keep_clearance` edits the goal in place** [code]. `_goal.y` is raised; if the AI
    keeps a reference to the same vector for something else, it sees the raised value.
13. **The death fall depends on the die clip** [code + test]. `DEATH_FALL_TIME` (2.5 s)
    assumes the body is removed 3.5 s after death (Mothra: 30 frames at 10 fps + 0.5 s).
    A kaiju with a shorter die clip, or a drop above 105 nodes at the 30 n/s cap, still
    vanishes in mid-air. Before the fix Mothra fell at a fixed 8 n/s and was removed at
    y 30.7; now she lands at y 8.5 after about 2.6 s (`mothra_terrain` phase C). The drops
    spawn at the point of death and fall on their own. `death_fall` leaves the object
    `physical = true`.
14. **Bulldozing uses `pursuit_bonus`** [code]. `update_bulldoze` starts the straight
    walk at `self.pursuit_bonus`; later `gopath` calls during the bulldoze use whatever
    `speed_bonus` the caller passed (`check_pace` passes `pace_bonus`).
15. **Dig callbacks may expect a player** [code + test]. `core.dig_node` runs the node's
    `after_dig_node` with a nil digger. The `pcall` in `smash_node` keeps such an error
    from stopping the server, but whatever the callback wanted to do after the failing
    line is skipped. The warning in the log names the node (`kaiju_dig_callbacks`,
    `gojira_smash`).
16. **Settings are global, not per world** [code]. `griefing_enabled` reads
    `minetest.conf`. To stop the destruction in one world only, use Mineclonia's
    `mobs_griefing` gamerule there.
17. **Melee standoff only where the bulldozer is wired up** [code + test]. The standoff
    lives in `update_bulldoze` and `gopath`; a walking kaiju that calls neither walks
    into its target's body like any mcl_mobs mob. And it must stay `pushable` (the
    default), or nothing separates it from another kaiju it lands on (`kaiju_clinch`).

---

## 7. Game support and the VoxeLibre layer (`vl.lua`)

`init.lua` starts by choosing the mob API:

```lua
local mineclonia = mcl_mobs.mob_class.run_ai ~= nil
kaiju_core.voxelibre = not mineclonia and core.get_modpath("vl_projectile") ~= nil
```

Mineclonia's rewritten `mcl_mobs` has `run_ai`; VoxeLibre's older one doesn't, and VoxeLibre
ships `vl_projectile`. Any other game stops at an assertion that names the problem. On
Mineclonia `kaiju_core.mcl_mobs` is `mcl_mobs` itself, `mob_griefing(name)` calls
`mobs_mc.is_mob_griefing_enabled(name)` and `tile_drops()` returns
`mcl_vars.do_tile_drops`, so the code paths are the ones the mods always had. Every kaiju
mod starts with `local mcl_mobs = kaiju_core.mcl_mobs` and uses only that.

On VoxeLibre `init.lua` runs `vl.lua`, which sets `kaiju_core.mcl_mobs` to a table that
falls back to VoxeLibre's `mcl_mobs` and replaces:

| Name | What it does on VoxeLibre |
|---|---|
| `mob_class` | A class on top of VoxeLibre's: `on_step` runs `check_standin`, `navigation_step`, `motion_step`, `ai_step`, burning, `rotate_step`, `run_targeting_rules`, `run_ai` (Mineclonia's order), and none of VoxeLibre's state machine. It implements the methods listed in [`../README.md`](../README.md#api-comparison). |
| `register_mob` | Registers with VoxeLibre (`spawn_class`, `can_despawn = false`, `initial_properties` with boxes, size and HP), then copies the definition's other fields (methods, `_fields`) onto the entity (with `rawget`: VoxeLibre's class has methods of the same names) and sets the class as its metatable. A kaiju saved while dead is removed on activation (VoxeLibre removes the body with `core.after`, which a restart loses). `on_activate` runs VoxeLibre's, then sets `self.collisionbox` and calls `post_load_staticdata`. |
| `register_arrow` | `_lifetime` × 0.05 (steps → seconds); a raycast along the path, then the stock 1.5-node radius (the raycast skips players without `enable_pvp`); a hit on a `kaiju_core:hitbox` goes to its owner via `hit_mob`; the shooter and its hit boxes are never hit (`allow_punching`). |
| `get_arrow_damage_func` | Passes the shooter as the source, so the victim retaliates. |
| `build_*_target_rule` | Own implementations with Mineclonia's semantics (seek every 0.5 s, sight persistence 3 s, retaliation 15 s). `build_alert_receiver_rule` returns a rule that never fires. |

Constants in `vl.lua`: `SPEED` 0.8 nodes/s per `movement_speed` (Gojira's 7.5 gives the
6 n/s measured on Mineclonia), `SWIM_SPEED` 5/3 per `water_velocity`, `GRAVITY` 14.7,
`JUMP` 7 (against a wall), `RISE` 4 (vertical speed in water), `TURN_RATE` 5 rad/s,
`PUSH` 3 n/s (out of an overlapping kaiju; other mobs don't push), `PACE_TIMEOUT` 15 s.

Gotchas on VoxeLibre:

1. **Straight lines only**: `gopath` is `go_to_stupidly`. `waypoints` and
   `pathfinding_context` are always `nil`; code that drops a pathfinder path before a
   straight walk (`cancel_navigation` in gojira's retreat, cthulhu's `walk_home`) is
   harmless there.
2. **VoxeLibre's own mobs** have no `dead` field and no `collisionbox` field. The layer's
   target checks use `state == "die"` and `health`; anything that reads another mob's box
   needs `obj:get_properties().collisionbox` as a fallback (cthulhu's `can_grab` does).
3. **Damage**: punches (`on_punch`), `mcl_util.deal_damage` (the entity's `deal_damage`)
   and VoxeLibre's `damage_mob` all end in `receive_damage`, which records the attacker
   and calls `check_for_death(reason, damage)`; that one calls VoxeLibre's
   `check_for_death` (flash, sounds, drops, XP, `on_die`, die clip, removal) and sets
   `self.dead`.
4. **Staticdata**: VoxeLibre's `get_staticdata` clears `attack` and `state` on the live
   entity at every save; the layer restores them. Transient tables with ObjectRefs inside
   (`_targets_visible`, `_object_search_lists`) are dropped before serializing.
