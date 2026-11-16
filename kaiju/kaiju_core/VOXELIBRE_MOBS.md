# VoxeLibre 0.92.4 mob system: reference for kaiju work

Durable notes on how VoxeLibre's mobs actually behave, read from the source (static reading;
nothing here was run unless it says so). Companion to `README.md` §7 (the compat layer,
`vl.lua`) and the API comparison table in `../README.md#api-comparison`. Navigation parity
plan: the scratch plan for `vl_path.lua` is not repeated here.

**Source root.** All `file:line` references are relative to
`~/.minetest/games/mineclone2/mods/` (VoxeLibre 0.92.4, read-only). Abbreviations:

| Short | Path |
|---|---|
| `mcl_mobs/` | `ENTITIES/mcl_mobs/` |
| `mobs_mc/` | `ENTITIES/mobs_mc/` |
| `mcl_burning/` | `ENTITIES/mcl_burning/` |
| `vl_projectile/` | `ITEMS/vl_projectile/` |
| `mcl_potions/` | `ITEMS/mcl_potions/` |
| `mcl_util/`, `mcl_explosions/` | `CORE/mcl_util/`, `CORE/mcl_explosions/` |

Line numbers drift between VoxeLibre releases; the function name is the stable anchor.
`mcl_mobs/api.txt` is the old upstream documentation; it is partly stale, trust the code.

Items marked **(bug?)** are code that looks wrong as written. They are observations from
reading, not confirmed in a running world.

---

## 1. Module layout of `mcl_mobs`

`mcl_mobs/init.lua:1-37` creates the globals and `dofile`s the parts in this order:

| File | Lines | Role |
|---|---|---|
| `init.lua` | 775 | Globals (`mcl_mobs`, `mob_class`, `mob_class_meta`, `registered_mobs`), `register_mob` (:115), `register_conversion` (:431), `get_arrow_damage_func` (:455), `register_arrow` (:463), spawn egg code (`on_place_egg` :635, `register_egg` :740) |
| `functions.lua` | 150 | `mcl_mobs.check_line_of_sight` (:8), `mcl_mobs.target_visible` (:105) |
| `effects.lua` | 440 | Particles, sounds (`mob_sound` :95), texture mods, `death_effect` (:53), animation (`set_animation` :279, `get_animation_speed` :256), head swivel |
| `physics.lua` | 1056 | `item_drop` (:137), `set_velocity` (:262), yaw helpers, `check_for_death` (:466), `do_env_damage` (:651), `step_damage` (:852), `damage_mob` (:884), cramming (:898), `falling` (:931), `check_dying`, `check_suspend` |
| `movement.lua` | 719 | cliff/water danger checks, `do_jump` (:240), `replace_node` (:350), runaway/follow, `flop`, `go_to_pos` (:543), `do_states_walk/stand/runaway` |
| `items.lua` | 115 | Armor textures/groups for `wears_armor` mobs, `check_item_pickup` |
| `pathfinding.lua` | 547 | `gopath` (:177), `check_gowp` (:404), door handling |
| `combat.lua` | 1233 | `smart_mobs` (:58), targeting (`monster_attack` :289, `npc_attack` :393), `on_punch` (:504), `check_aggro`, explosions (`boom` :460), `do_states_attack` (:913) |
| `api.lua` | 559 | `get_staticdata` (:67), `mob_activate` (:113), `do_states` (:297), `on_step` (:346-452), lifetimer, `/clearmobs` |
| `breeding.lua`, `mount.lua`, `crafts.lua`, `lucky_block.lua` | | Taming/breeding, riding, nametag/lasso recipes. Not covered here. |
| `spawning.lua` | 1293 | Spawn dictionary, natural spawn loop, `mcl_mobs.spawn` (:626), despawn |
| `compat.lua` | 32 | Wrappers so `mcl_mobs:register_mob(name, def)` (old colon style) still works (:5-32) |

Mob definitions live in `mobs_mc/<name>.lua`. VoxeLibre renamed several vanilla mobs:
enderman is `mobs_mc:rover` (`rover.lua`), creeper is `mobs_mc:stalker` (`stalker.lua`),
zombified piglin etc. See `grep -h 'register_mob("' mobs_mc/*.lua`.

Entry hooks. A mob entity is `setmetatable(final_def, mob_class_meta)` (`init.lua:419`), so the
engine's instances look up methods in `final_def` and then in `mob_class`. `on_step`,
`on_punch`, `get_staticdata` are the **class's** methods, not the definition's (see §2 and §13).

---

## 2. `register_mob(name, def)` (`mcl_mobs/init.lua:115-419`)

`mcl_mobs.register_mob` is wrapped by `compat.lua` so both `mcl_mobs.register_mob(n, d)` and
`mcl_mobs:register_mob(n, d)` work.

### Hard requirements and side effects
- `assert(def.spawn_class)` (:116). Values seen: `"hostile"`, `"passive"`, `"ambient"`, `"water"`,
  `"water_ambient"`, `"water_underground"`, `"axolotl"` (the cap keys, spawning.lua:75-86) The mob cap code keys on it.
- `mcl_mobs.spawning_mobs[name] = true`, `mcl_mobs.registered_mobs[name] = def` (the **raw** def)
  (:118-119).
- `can_despawn` default: `def.spawn_class ~= "passive"` (:121-122).
- With `doc_identifier` installed, registers a doc entry (:407-417).
- Then `minetest.register_entity(name, setmetatable(final_def, mob_class_meta))` (:419).

### The whitelist rule
`final_def` (:178-402) is built from a **fixed list of fields**. Every `def` field not named
there is silently **dropped** (not copied to the entity). This includes custom `_fields`,
`on_step`, `on_punch`, `get_staticdata`, `on_deactivate`, `mesh`/`textures` inside
`initial_properties`, etc. Use the hooks below instead.

### Fields copied as-is (with `or` default)
Defaults in parentheses; `nil` means the field stays `nil` on the entity.

| Group | Fields |
|---|---|
| Identity | `name`, `description`, `type` (`"monster"`, `"animal"`, `"npc"`), `spawn_class`, `owner` (`""`), `order` (`""`), `nametag`, `ignores_nametag` (false) |
| Stats | `damage` (0, scaled), `armor` (100), `reach` (3), `view_range` (16), `walk_velocity` (1), `run_velocity` (2), `follow_velocity` (2.4), `jump_height` (4), `stepheight` (0.6), `fall_speed` (-14.715), `fall_damage` (1), `lifetimer` (57.73), `explosion_timer` (3), `attack_frequency` (nil, used as 1), `shoot_interval` etc. |
| Environment | `light_damage` (0), `sunlight_damage` (0), `water_damage` (0), `lava_damage` (**8**), `fire_damage` (1), `rain_damage` (0), `breathes_in_water`, `ignited_by_sunlight`, `fire_resistant`, `fire_damage_resistant` |
| Movement | `fly` (false), `fly_in` (table, see below), `floats` (1), `floats_on_lava` (0), `fear_height` (0), `walk_chance` (50), `jump` (`~= false`), `rotate` (rad), `noyaw` |
| Combat | `attack_type`, `passive` (false), `attack_animals` (false), `attack_npcs` (false), `specific_attack`, `extra_hostile`, `attack_exception`, `group_attack` (false), `owner_loyal`, `runaway`, `runaway_from`, `knock_back` (`~= false`), `immune_to` (`{}`), `docile_by_day` (false), `pathfinding`, `custom_attack`, `double_melee_attack`, `dogshoot_switch`, `dogshoot_count_max` (5), `shooter_avoid_enemy`, `strafes`, `avoid_distance` (9), `arrow`, `shoot_arrow`, `shoot_offset` (0), `shoot_pos` (zero), `explosion_strength/radius/damage_radius`, `explosiontimer_reset_radius`, `allow_fuse_reset` (`~= false`), `stop_to_explode` (`~= false`), `dealt_effect` |
| Spawning | `spawn_check`, `can_spawn`, `spawnbox` (= collisionbox), `spawn_in_group`, `spawn_in_group_min`, `on_spawn`, `spawn_small_alternative`, `_spawner` |
| Visual | `textures` (kept as `texture_list`), `child_texture`, `animation` (`{}`), `sounds` (`{}`), `sounds_child`, `child_animations` (renamed `_child_animations`), `head_swivel` etc. |
| Misc | `drops` (processed, below), `follow`, `nofollow`, `can_open_doors`, `pick_up`, `wears_armor`, `replace_*` (rate/what/with/offset/delay/on_replace), `particlespawners`, `is_boss`, `harmed_by_heal`, `child`, `xp_min/xp_max` (0), `_vl_projectile` |

### Fields transformed
- **`fly_in`** (:131-146): string, list, or `{key=true}` map becomes a set `{[nodename]=true}`;
  default `{air=true}`. Used by `flight_check`, `has_room`.
- **`initial_properties`** (:152-176, 207-224). Only `hp_min`, `hp_max`, `breath_max` and
  `collisionbox` are read from `def.initial_properties`. Everything else comes from **top-level**
  def fields: `mesh`, `visual`, `visual_size` (`{x=1,y=1}`), `glow`, `use_texture_alpha`,
  `makes_footstep_sound`, `stepheight`, `selectionbox` (= collisionbox). Fixed:
  `physical = true`, `automatic_face_movement_max_rotation_per_sec = 300`.
  - `hp_min`/`hp_max` go through `scale_difficulty(value, 5/10, 1)` (:124-131): equal to the
    default (5/10) is returned unchanged, otherwise `max(1, value * mob_difficulty)`.
    `damage` is scaled the same way (`damage = 0` stays 0).
  - Old-style top-level `hp_min`/`hp_max`/`breath_max` still work but log a warning (:149-158).
  - collisionbox default `{-0.25,-0.25,-0.25,0.25,0.25,0.25}` (:171); `_avg_radius` is the mean
    of `abs(box[i])` (:172-177), used for punch reach.
- **`drops`** (:161-170): each entry copied, `chance` default 1, `looting` default `"common"`,
  `min` default 1, `max` default `min`. `chance` means "1 in N" (see §5).
- **`on_rightclick`**: wrapped in `create_mob_on_rightclick` (:78-85): handles pet sit toggle
  and nametags first, then calls yours.
- **`on_blast`**: default punches the mob with `{fleshy = damage}` (:340-347).
- **`deal_damage(self, damage, reason)`** (:351-380): always installed. Marks `xp_timestamp` if
  the direct/source is a player, then calls `def.deal_damage` if given, else `damage_mob`.
- **`on_activate`** (:382-396, a second definition at :433 is `register_conversion`'s): sets
  `is_mob = true`, `collide_with_objects = false`, then `mob_activate(staticdata, def, dtime)`.
- **`attack_exception`** default `function(p) return false end` (:401).

### Fields that look settable but are not (the `or` traps)
| Source | Effect |
|---|---|
| `pushable = def.pushable or true` (:307) | always `true`; `pushable = false` is ignored |
| `suffocation = def.suffocation or true` (:238) | always `true`; the check is `self.suffocation == true` |
| `fall_damage = def.fall_damage or 1` | `0` works (0 is truthy in Lua) but the check is `== 1`, so only exactly `1` enables it |
| `floats = def.floats or 1` | `0` works, `false` becomes 1 |
| `lava_damage = def.lava_damage or 8` | `false` becomes 8; use `0` to disable |
| `fire_damage = def.fire_damage or 1` | same, use `0` |
| `damage = scale_difficulty(def.damage, 0, 0)` | returned as is when 0; otherwise multiplied by `mob_difficulty` |
| `can_despawn` | `false` honoured (explicit nil check), default depends on `spawn_class` |

### Hooks available (all called with the mob as `self`)
`do_custom(self, dtime)` (every step, returning `false` aborts the rest of the step),
`do_punch(self, hitter, tflp, tool_caps, dir)` (return `false` to cancel the punch),
`on_die(self, pos, cmi_cause)` (return `true` = remove immediately, no drops), `on_corpse_remove`,
`deal_damage`, `on_blast`, `on_spawn` (once, returns truthy to mark done), `after_activate`,
`on_breed`, `on_grown`, `on_pick_up`, `on_replace`, `on_lightning_strike`, `can_spawn(pos)`,
`spawn_check`, `attack_state(self, dtime)` (for `attack_type = "custom"`), `on_attack`,
`custom_attack(self, target_pos)`, `shoot_arrow(self, pos, dir)`, `do_teleport`,
`detach_child`, `on_rightclick`.

---

## 3. The per-step pipeline

`mob_class:on_step(dtime, moveresult)` (`api.lua:438-452`) wraps `on_step_work` in `pcall`
unless the setting `mcl_development` is on (:440). An error aborts the step and prints a
"Bug report start" block via `log_error` (:416-423); the mob keeps living. **A bug in your
`do_custom` shows up only in the log.**

`on_step_work` (`api.lua:346-436`), in order:

1. `check_despawn(pos, dtime)` (:349, spawning.lua:1261). May remove the mob and stop the step.
2. `outside_limits()` (:350): close to the mapgen edge forces `stand`.
3. `check_death_and_slow_mob()` (:354, physics.lua:248): `check_dying()`, then **damps horizontal
   velocity by 0.7 per step** (0.92 while dying).
4. `falling(pos, moveresult)` (:359, physics.lua:931): gravity, water buoyancy, fall damage.
5. `step_damage(dtime, pos)` (:360, physics.lua:852): `mcl_burning.tick` unless `fire_resistant`;
   every ~1 s: cramming check, `do_env_damage`, `replace_node`.
6. `if state == "die" then return` (:362). A dying mob only gets steps 1-5.
7. `player_in_active_range()` (:365): any player within `mcl_mob_active_range` (default **48**,
   physics.lua:67-74). `check_suspend` (:366): with no player in range, the mob is frozen
   (animation `stand`, velocity and acceleration zeroed if on ground).
8. `check_water_flow` (:367), `_can_jump_cliff` (:368), `flop` (:369), `check_smooth_rotation` (:370).
9. Only if a player is in range (:372-390): `set_animation_speed`; **`add_velocity(self.acc)`**
   (see below); `check_head_swivel`; every 0.2 s `check_follow`, `check_runaway_from`,
   `monster_attack`, `npc_attack`; `check_herd` (every 4 s, a global timer shared by all
   mobs, movement.lua:556-575); `do_jump` (:389).
10. Every 1 s (:392-399): item pickup, armour texture, opinion sound, `check_breeding`.
11. `check_aggro`, `check_particlespawners` (:401-402).
12. `do_custom(self, dtime)` (:403). `== false` ends the step.
13. `do_states(dtime, player_in_active_range)` (:404, api.lua:297).

### Movement is "acceleration added as velocity every step"
`set_velocity(v)` (physics.lua:262-290) does not set a velocity. It stores `self.acc =
(-sin(yaw)*v*0.4 + push_x, 0, cos(yaw)*v*0.4 + push_z)`; step 9 then calls
`object:add_velocity(self.acc)` **every step** and step 3 multiplies x/z by 0.7 each step. That
makes the steady speed about `0.4*v/0.3 = 1.33 v` (derived from the code, not measured), and the
result depends on the server step length. It also means: no player in range, no movement
(step 9 is skipped); `set_velocity(0)` leaves only the push term.

`set_velocity` returns `false` and does nothing if the mob is not `fly`, `v ~= 0`, and neither
`self._grounded` (set in `falling`) nor `self.in_water` (set in `do_jump`, which does not run
for `jump = false` mobs) is true. `pushable` mobs add `collision()` pushes from other mobs and
players (physics.lua:220-246).

### `do_states` (`api.lua:297-324`)
1. `pause_timer > 0` (set by knockback, 0.25 s): count down and return, no behaviour at all.
2. `env_danger_movement_checks` (movement.lua:208): cliff/water-danger turn-aways, only for
   `walk` (not `gowp`, `attack`, `stand`, `runaway`).
3. Dispatch on `self.state`:
   - `"gowp"` (`PATHFINDING`): `check_gowp(dtime)` every step.
   - `"attack"`: `do_states_attack(dtime)` every step; returns true if the mob exploded.
   - otherwise only once a second (`check_dtime_timer "onstep_dostates"`): `stand`
     (movement.lua:653), `walk` (:589), `runaway` (:706).

State values: `stand`, `walk`, `runaway`, `attack`, `gowp`, `die`, `flop` (set by `flop()` for
`fly` mobs out of their medium), `""` (transient), mob-specific (`rover`: `staring`).
`order` values: `"stand"`, `"sit"`, `"follow"`, `"sleep"`, `"work"`. `order == "stand"` stops
wandering **and `do_jump`** (movement.lua:241).

- `stand` (:653-704): 25% chance per second to turn (look at a player within 3 if
  `look_at_players`, or toward `_home`/`_bed`); `walk_chance`% to start walking (blocked by
  `order`, by `facing_fence`, and by `is_at_cliff_or_danger`).
- `walk` (:589-651): leaves water/danger toward land (`find_nodes_in_area_under_air`, `group:solid`);
  30% back to `stand`; turns at walls; walks at `walk_velocity`.
- `runaway`: counts seconds, stops after 5 or at a cliff, then turns by ~PI.
- `runaway` as a def field (a boolean) means "flee when punched" (combat.lua:769); `runaway_from`
  (a name list, `"player"` included) means "flee from these on sight" (movement.lua:411).

### `smart_mobs` and pathfinding while attacking
`attack` state only calls `smart_mobs(s, p, dist, dtime)` (combat.lua:58) when `self.pathfinding`
is set (1 or 2) and `dist > reach`. See §6. `pathfinding = 2` may dig and build (griefing, §8).

### Attack types (`do_states_attack`, combat.lua:913-1233)
| `attack_type` | Behaviour |
|---|---|
| `"explode"` (:971) | Walk at `run_velocity`; fuse starts within `reach` and in sight; fuse resets beyond `explosiontimer_reset_radius` or out of sight if `allow_fuse_reset`; blinks every 0.2 s; at `explosion_timer` calls `mcl_explosions.explode(center, explosion_strength, {griefing=mobs_griefing, grief_protected=false}, self.object)` and removes the mob (:1021-1032) |
| `"dogfight"` (:1036) | Turn to target; if `fly` and above/below, adjust vertical velocity; beyond `reach` run (`walk_velocity` if `path.stuck`, never set), unless `is_at_cliff_or_danger`; within `reach` and in sight and `timer > attack_frequency` (1): animation `punch`/`punch2`, `target:punch(self.object, 1.0, {full_punch_interval=1.0, damage_groups={fleshy=self.damage}})` (:1121-1131), optional `dealt_effect` via `mcl_potions.give_effect_by_level`, or `custom_attack(self, target_pos)` |
| `"shoot"` (:1151) | `strafes` or stand still; every `shoot_interval` seconds with 60% chance and a clear raycast, creates `vl_projectile.create(self.arrow, {pos, owner=self})` or calls `shoot_arrow` |
| `"dogshoot"` | Alternates shoot / dogfight by `dogshoot_switch` timers (`dogswitch`, :434) |
| `"custom"` (:1228) | Calls `attack_state(self, dtime)` |
| any | `on_attack(self, dtime)` is called at the end (:1232) |

Operator precedence note: the `dogfight` condition (:1036-1038) mixes `or` and `and` without
parentheses; `dogshoot` entry into the melee branch is subtle.

Giving up: `do_states_attack` clears aggro when the target is gone, out of `view_range`, dead
(`target:get_hp() <= 0`, the **engine** HP, §5), invisible (`mcl_mobs.invis`), or a creative
player (:922-933). Out of sight for more than 15 s (`TIME_TO_FORGET_TARGET`, :14, using
`os.time`) also clears; while out of sight the mob pursues `path.last_seen_target_pos` (:940-960).

### Jumping (`do_jump`, movement.lua:240-328)
Skipped for `jump = false`, `jump_height = 0`, `fly`, `order == "stand"`. Requires a walkable node
in front at +0.5 (or `walk_chance == 0`), no solid node at +1.5 unless attacking (so 2-high walls are
not attempted unless the mob attacks), not fences/walls/gates (`facing_fence = true`). Sets `v.y =
jump_height + 0.3` (4.3 default), x1.5 vertical in water, x2.5 horizontal for cliff jumps, and
re-applies a forward acceleration at +0.1/0.2/0.3 s. After 4 jumps with nearly no horizontal
speed, it turns randomly. `go_to_pos(b, speed)` (:543) jumps if `b.y > s.y + 0.2`.
Cliff jumping (`can_jump_cliff`, :81-120): gap in front with ground 1.6 or 2.5 nodes ahead.

### Animations
`set_animation(anim, fixed_frame)` (effects.lua:279-311) looks up `animation[anim.."_start"]`
and `_end`; unknown names return silently; `<anim>_loop ~= false` loops; `_speed` or
`speed_normal` (15) times `frame_speed_multiplier`; walk/run/fly speed scales with `v/run_velocity`
(:256-277). `anim_locked` blocks changes (:280). In `die`, only `die` and `stand` are accepted
(:288). `fly` and `flight_check()` turn `walk` into `fly` (:290). Jockeys force `jockey`.

### Despawn
- `check_despawn` (spawning.lua:1261-1279): `lifetimer -= dtime`; only when
  `despawn_allowed` (below). At `<= 0` or `despawn_immediately`, remove. At `<= 10`, 30%
  `despawn_immediately`, otherwise reset to 20.
- `update_lifetimer` (api.lua:455-472): once a second, every mob within **47** nodes of any player
  gets `lifetimer = max(20, lifetimer)` and `despawn_immediately = false`.
- `despawn_allowed` (spawning.lua:1230-1239): `can_despawn == true`, no nametag, not `attack`
  state, `following == nil`, not `tamed`, not `persistent`.
- **(bug?)** `mob_class:despawn_allowed()` (:1241-1243) has **no `return`**. `get_staticdata`'s
  "remove on unload when far" (api.lua:73) therefore never fires: mobs that unload with their
  mapblock are saved, not removed. `check_despawn` uses the local function and works.
- `/clearmobs [all|monster|passive|<name> [range|nametagged|tamed]]` (api.lua:475); `maphack` priv.

---

## 4. Targeting

All in `combat.lua`; run every 0.2 s while a player is in range (api.lua:379-383).

### `monster_attack` (:289-391)
Returns early if `enable_damage` is off (read **once at load**, :3) unless `force_attack`;
if `self.passive ~= false`; if already `attack`; or `day_docile()` (`docile_by_day` and
`time_of_day` in 0.2-0.8, updated once per second in `do_env_damage`).

1. Scan objects within `view_range`. Same-`type` hostile mobs already attacking something put
   their target in a blacklist (:304-317), so a pack spreads over targets.
2. Per object, classify: players (skipped if `mcl_mobs.invis`, outside `object_in_range`
   (which applies `mcl_armor.player_view_range_factors` per mob name, physics.lua:76-97), or
   creative) count as target type `"player"` only if `self.type == "monster"` or `self._aggro`;
   entities use their own `.type` and `.name`.
3. Candidate filter (:344-350): `specific_attack` list contains the name (nil list = all), AND
   (type is `player`, OR `npc` with `attack_npcs`, OR `animal` with `attack_animals == true`, OR
   `extra_hostile` and `not attack_exception(obj)`).
   Targets of type `monster` are never valid by default. A mob type `"monster"` cannot target
   another monster unless `extra_hostile` is set.
4. Pick the nearest candidate with line of sight (`target_visible(self.object, target)`) that
   no pack member is already on.
5. `do_attack(obj)` immediately if within a 60 degree cone in front (`target_in_direct_sight`,
   :255), else `delayed_attack` 0.5-1.0 s later (re-checks sight, :275).
**(bug?)** `type` and `name` are declared once outside the loop (:295) and not reset per
object: a non-mob entity (no luaentity) inherits the previous object's `type`/`name` and may
pass the filter.

### `npc_attack` (:393-432)
Only `type == "npc"` with `attacks_monsters`: nearest visible `type == "monster"` mob.

### `do_attack(object)` (:38-56)
Refused in `attack`, `die`, `runaway` states; for players if `enable_damage` is off and not
`force_attack`. Sets `self.attack = object`, `self.state = "attack"`.

### Owner / team rules
There are **no teams or factions**. What exists:
- `owner` (player name string, `""` default), `tamed`, `owner_loyal`.
- `on_punch` (combat.lua:790-843): the puncher is attacked back if `passive == false`,
  state not `flop`, adult (`child == false`) or monster, `hitter:get_player_name() ~= self.owner`,
  and the puncher is not in `mcl_mobs.invis`. It sets `_aggro = true` (:808).
- Alert (:811-843): all luaentities within `view_range` of the **hitter** with `group_attack`
  (truthy) and `state ~= "attack"` and `owner ~= puncher`: same-name mobs `do_attack(hitter)`;
  if `group_attack` is a table of names, mobs listing `self.name` attack too and get `_aggro`.
  Mobs with `owner == puncher` and `owner_loyal` attack the mob that was hit (`do_attack(self.object)`).
- `check_runaway_from` skips the owner player (movement.lua:423).
- `monster_attack` has **no owner check**: a tamed `type = "monster"` mob targets its owner.
- `mcl_mobs.invis[player_name]` (set by `invisibility`-style mods) hides a player from mob
  targeting, following, and aggro.

### Line of sight (`functions.lua`)
- `mcl_mobs.check_line_of_sight(origin, target, seethru)` (:8): raycast over nodes
  (`objects=false, liquids=true`); a node blocks only if walkable and not `seethru` (default
  `{air=true}`) and the **collision boxes** (slab test) intersect the segment (:62-69).
  Water, plants, lava (non-walkable) do not block. Leaves, glass do.
- `mcl_mobs.target_visible(origin, target, check_feet, seethru)` (:105): origin may be a
  position or object; an object origin is raised to `head_eye_height` or 85% of its collisionbox.
  Rays go to the target's **head** (`pos + box[5]`) and, by default, its **feet** (`box[2]`);
  either ray succeeding is enough. Targets with huge boxes are therefore easy to see.
- `mob_class:target_visible(origin, target)` (movement.lua:67) is the method form (`target`
  falls back to `self.attack`); `line_of_sight` (movement.lua:77) calls `check_line_of_sight`.
- **(bug?)** `smart_mobs` calls `self.target_visible(self.object, self.attack)` (combat.lua:67)
  with a dot, so `self` inside is the ObjectRef and `target` ends up nil: `has_lineofsight` is
  always `false` there. The LOS-switch trigger for path recalculation works off that.

### Following and aggro bookkeeping
`check_follow` (movement.lua:455): follows a player holding `follow` item(s) within
`view_range`; `follow_velocity` 2.4, stops within 3 nodes. `check_aggro` (combat.lua:845) drops
aggro beyond 128 nodes (rarely relevant). `force_attack` bypasses `enable_damage` checks.

---

## 5. Damage and death

### `mob_class:on_punch(hitter, tflp, tool_caps, dir)` (combat.lua:504-843)
Flow, in order:
1. **0.5 s invulnerability** after each *counted* hit (`invul_timestamp`, :507-511, set at :703).
   Applies to arrows, explosions-by-punch, everything that goes through `on_punch`.
2. Player puncher: reach check (distance minus `_avg_radius` vs `weapon range` or 3, skipped in
   creative); `self.protected` and `is_protected`; sets `xp_timestamp`. Non-player puncher: if the
   hitter entity has `_owner` naming an online player, set `xp_timestamp` (so a player's arrows
   give XP).
3. `do_punch(...)` hook; `false` cancels. `tool_capabilities == nil` returns (:547-551).
4. Creative player with `vl_creative_instant_kill` (default true) sets `health = 0`.
5. **Damage formula** (:569-576): for every group in `tool_capabilities.damage_groups`:
   `damage += value * clamp(tflp / full_punch_interval, 0, 1) * (armor[group] or 0) / 100`.
   The armor table is `object:get_armor_groups()` (see "armor" below). **A damage group the mob
   has no armor entry for deals 0.** Then multiplied by `strength` and `weakness` effect factors
   of the hitter (:579-583).
6. Fire aspect sets the mob on fire (`level*4` s); bane of arthropods applies `slowness`
   (which `give_effect` refuses for mobs, §12).
7. `immune_to = {{itemname, damage}, ...}` replaces the damage for that wielded item (:597-602).
8. `damage <= -1` heals (`health - floor(damage)`) and returns early (:604-608).
9. Crit (hitter moving down) multiplies by 1.5-2.5. If `damage >= 0.1`: sound, `damage_effect`,
   `self.health -= damage` (**not floored**, unlike `damage_mob`), set `invul_timestamp`,
   `check_for_death("hit", {type="punch", puncher=hitter}, {attacker_name=...})`.
   **Damage below 0.1 is dropped completely (no health loss, no invulnerability, no death
   check)**, but the knockback block below still runs for any `damage >= 0`.
10. Knockback (:709-764) if `knock_back`: `kb = 1.25` (or `damage_groups.knockback`), `+3` per
    `hammer` group and `+3*knockback enchant` for players, scaled by punch charge, `x20`, then
    `add_velocity(dir * kb, up 5.25)`. `up = 0` if already airborne or `fly`. `pause_timer =
    0.25` freezes the AI. A kill sets `vl_drops_pos` and increases `kb` by 25%.
    Entity hitters use `hitter._knockback`.
11. If `runaway == true` the mob flees; else, if `passive == false` etc., it attacks the puncher
    (:790-809), then the alert code (§4).

### Armor groups
At activation (`api.lua:231-239`): `armor` as a table: `{...armor, immortal = 1}`; as a number:
`{immortal = 1, fleshy = armor}`. **`immortal = 1` is always set**, so engine-side damage
is disabled; health is the Lua field `self.health` (`hp_min..hp_max` random at activation if 0,
`api.lua:216`). `object:get_hp()` is **not** the mob's health: the mob code never
decrements it. Read `mcl_util.get_hp(obj)` (`mcl_util/init.lua:389`) or `self.health`.
`wears_armor` mobs rewrite `fleshy` from worn armour (`items.lua:17-66`).

### `mcl_util.deal_damage(target, damage, reason)` (`mcl_util/init.lua:361-388`)
For a luaentity: `luaentity:deal_damage(damage, reason)` if it has one (every VoxeLibre mob does),
else for mobs `damage_mob`. It **bypasses armor groups** and invulnerability. Reasons are
`{type=..., direct=obj, source=obj}`; `source`/`direct` players refresh `xp_timestamp`
(init.lua:352-356). Burning uses it: 1 dmg per second (`mcl_burning/api.lua:197`).

### `damage_mob(reason, damage, info)` (physics.lua:884-896)
`damage = floor(damage)`; if `> 0`: subtract, smoke, `check_for_death(reason, {type=reason}, info)`.
**Anything below 1 is discarded.**

### `check_for_death(cause, cmi_cause, info)` (physics.lua:466-589)
1. Returns true at once if `state == "die"`.
2. Returns false if `health == old_health and health > 0`. So code that edits `self.health`
   directly is picked up by the next step's `check_death_and_slow_mob → check_dying →
   check_for_death()` (with `cause = nil`, hence no "hit" semantics).
3. Still alive: clamp to `hp_max`; on damage, red flash (`^[colorize:#d42222:175` for 1 s) and
   `damage` sound; return false.
4. Dead: `mob_sound("death")`, then **`on_die(self, pos, cmi_cause)`** (:517-526). Returning
   `true` removes the mob immediately (`state = "die"`, extinguish, `remove_entity`) **and skips
   drops and XP**.
5. If `gamerule:doMobLoot` (default true): `drop_mob_items` + `drop_mob_xp` (:531-534).
6. `state = "die"`, `attack = nil`, `passive = true`, `pointable = false`, `collide_with_objects
   = false`, `set_velocity(0)`, acceleration = gravity. Extinguish is not called here.
7. Removal timing (:556-585): `instant_death` -> 0 s; else if `animation.die_start/die_end` exist:
   `(die_end - die_start) / (die_speed or 15) + 0.5` s with the `die` animation; else `1.5` s with
   `stand` and (via `check_dying`) a roll to lie on its side. Scheduled with `core.after` (lost
   on server restart/unload; the layer removes dead kaiju on activation, README §7).
8. `do_mob_corpse_remove` (:437-455): `on_corpse_remove(mob, pos)`, extinguish,
   `mcl_util.remove_entity` (sets `_removed`, calls `_on_remove`), `death_effect` particles.

### Drops (`item_drop`, physics.lua:137-217)
- Not for baby (`child`) non-monsters. Uses `vl_drops_pos` (set on a knockback kill) or the
  current position. Respects the `mobs_drop_items` setting (default on, physics.lua:35).
- Per entry: `chance` is "1 in N" (`1/chance`; `0` means never, :122-124). `looting = "common"`
  entries get `+0..looting_level` extras; `"rare"` entries add `looting_factor` (0.01) per
  level and drop **only for player kills**. `conditions.guarantee_if_killed_by` lists attacker
  entity names that force the drop (:114-119).
- `cooked = true` (killed by lava/fire, burning, or fire aspect) replaces items by their cooking
  result.
- Items are thrown with velocity (+-0.75, 6, +-0.75). `self.drops = {}` afterwards, and worn
  armour drops too.
- **(bug?)** `drop_mob_items` passes `looting = looting` (physics.lua:427-432) but `item_drop`
  reads `params.looting_level` (:140), so looting never applies.
- `drops` come from the entity's `self.drops`; changing them in `do_custom` works.

### XP (`drop_mob_xp`, physics.lua:394-407)
Needs a "player kill": `xp_timestamp` within 5 s (`PLAYER_KILL_TIME_US`, :8), set by player
punches, damage with a player as direct/source, or projectiles owned by a player; baby animals
give none; `random(xp_min, xp_max)`; none if the puncher is creative; `mcl_sculk.handle_death`
may absorb it; otherwise `mcl_experience.throw_xp(pos, amount)`.

### Other damage sources
- Explosions: `mcl_explosions` computes `floor((impact^2 + impact)*7*strength + 1)` and calls
  `mcl_util.deal_damage` (`mcl_explosions/init.lua:307-342`); knockback only for players or
  entities with `tnt_knockback`.
- Cramming: more than `gamerule:maxEntityCramming` (24) mobs within 1 node: 3 damage per env tick
  (~1 s) to the flagged mobs (physics.lua:898-929, 11-17).
- Fall: below.

---

## 6. Movement and navigation

### Primitives
- `set_velocity(v)`: see §3 (acceleration trick, grounded or in water requirement).
- `turn_by`, `turn_in_direction(dx, dz, delay)`, `set_yaw(yaw, delay)` (physics.lua:327-349):
  these set `target_yaw` and `delay` (smoothing steps); the actual rotation is applied in
  `check_smooth_rotation` (:351). `set_yaw` is ignored while `_kb_turn` or `noyaw`.
- `go_to_pos(b, speed)` (movement.lua:543): within 0.4 nodes returns true; jump if the target is
  more than 0.2 above; turn; `set_velocity(speed or walk_velocity)`; animation walk/run.
- `mcl_mobs.node_ok` (init.lua:11): `get_node_or_nil` with a fallback for unknown/unloaded.

### `gopath(target, callback_arrived, prioritised)` (pathfinding.lua:177-346)
The general-purpose pathfinder (villagers, golems), **not** used by attacking mobs.
- Does nothing while already `gowp`, or if `ready_to_path` is false (:99-113): after a failed
  plan wait 30 s (`_pf_last_failed`); otherwise at most one non-prioritised plan **per 4 s
  globally** (`os.time` granularity).
- **Clears `self.order`** (:182). On arrival (`check_gowp`, distance `< 1.8`, :418-432) it sets
  `order = "stand"`, which blocks wandering and jumping afterwards.
- Start/target are moved to an open node (`find_open_node`, :167-175); a target inside a solid
  node (job site) is moved up one.
- `core.find_path(p, t, 25, 1, 4)` (search distance 25, max jump 1, max drop 4); on failure it
  tries a path through the nearest door to the target, then to the origin, then through two doors
  (:203-261). Postprocessing handles carpets, doors, fence gates (`mcl_mobs_open_gates`
  setting), fences/walls (detours, :280-322).
- Sets `state = "gowp"`, `_target`, `current_target`, `waypoints` (list of `{pos, failed_attempts,
  action?}`), `callback_arrived`; returns `true`. On failure the mob turns toward the target
  and falls back to `walk`, returns `nil`.
- `check_gowp(dtime)` (:404-547), every step in `gowp`: arrival (<1.8, 3D), skip a waypoint if the next
  is closer and the current is within 1.5, advance at `< 0.9` (`0.7` for door actions; Y counts half),
  smoothing 70/30 toward the next waypoint, `run_velocity` when more than 15 waypoints remain, else
  `walk_velocity`. After the last waypoint, `failed_attempts` counts steps and abandons the route at
  **200** steps (`PATHFINDING_FAIL_THRESHOLD`).
  `waypoints == nil` on that code path throws (`#self.waypoints`), swallowed by `pcall`.
- Door actions (`interact_with_door`, :347-385) open and close door nodes along the way.

### `smart_mobs` (combat.lua:58-253), the attack-state pathfinder
- Called each step of `attack` when `dist > reach` and `self.pathfinding` is set.
- Stuck detection: horizontal movement `< 0.5` accumulates `path.stuck_timer`; `> 3 s` (not
  following) or `> 10 s` (following) triggers a plan. Also triggers on LOS loss switch and when
  `|dy| > stepheight`.
- Plan: positions are rounded, `core.find_path(s, p, 16, jumpheight, dropheight, "A*_noprefetch")`;
  `jumpheight = min(ceil(jump_height*0.25), 4)` if `jump` and `jump_height >= 4`, else 1 if
  `stepheight > 0.5`, else 0; `dropheight = fear_height` or 12. 1-wide, distance 16.
- Found: `path.way`, `path.following = true`; `do_states_attack` then steers at `path.way[1]`
  (waypoints popped at `< 0.6` Manhattan distance; paths longer than 50 are dropped,
  combat.lua:1052-1062). `self.state = ""` then `do_attack` re-enters `attack`.
- Not found, `pathfinding == 2` and `mobs_griefing`: digs/builds (§8).

### What the kaiju use instead
Neither of the two: both plan for a mob one node wide with `core.find_path` (which checks one
node and the one below it, no body height, no water), and both are tied to VoxeLibre's state
machine (`state = "gowp"`, `order`, `os.time` rate limits), which the layer does not run. The
kaiju's paths come from `vl_path.lua`, a height-field A* for a wide body (see `README.md` §7,
"Pathfinding on VoxeLibre"). `core.get_node_raw(x, y, z)` returns the content id without
building a node table; unloaded positions give `CONTENT_IGNORE`. It costs about 0.3 µs per
call from a mod's loop here (measured in the nav_* scenarios), not the 0.04 µs of a tight
benchmark loop.

### Water, floating, flying, swimming
- **Non-flying mobs** (`falling`, physics.lua:931-991): gravity `fall_speed` as acceleration;
  max fall speed is `fall_speed`; touching the ground sets a tiny gravity (`fall_speed*0.01`) and
  `_grounded = true`. In water (node at feet has `group:water`) and `floats == 1`, if the node at
  the top of the collisionbox (-0.25) is also water, acceleration is `-fall_speed / max(1, vy^2)`
  (buoyancy). Lava with `floats_on_lava == 1` likewise. Mobs in water jump (`do_jump` x1.5).
- **`fly = true`** (`falling` returns early unless dying): no gravity, no fall damage, no
  `_grounded` requirement. `fly_in` is the set of media the mob may be in (`air` by default; fish use
  water source names, e.g. `mobs_mc/cod.lua:53-54`). `flop()` (movement.lua:514) switches to
  state `flop` with gravity when `flight_check()` fails (`standing_in` not in `fly_in`,
  `"ignore"` counts as inside) and hops on solid ground; it returns to `stand` when back inside.
  **`standing_in` is refreshed only by `do_env_damage`, about once per second.**
- Vertical movement of `fly` mobs is the mob's own job; the stock code only adjusts it in the
  `dogfight` branch (`+/-walk_velocity` while in the medium, `+/-0.01` outside, combat.lua:1043-1062).
- `breathes_in_water`: drowning counts when neither feet nor head are in water instead.
- **Fall damage** (physics.lua:975-990): only if `fall_damage == 1`, not in water, velocity.y
  exactly 0 (landed), node below not air/ignore, drop `d = old_y - y > 5`:
  `damage = d - 5`, increased by the below node's `fall_damage_add_percent` group;
  `damage_mob("fall", ...)` (floored, so needs `d >= 6`). `old_y` updates only when landing on
  non-water ground.
- Danger avoidance for walkers (`is_at_cliff_or_danger`, movement.lua:122-164): `fear_height 0`
  disables; looks one node ahead; avoids drops of `>= fear_height` (probabilistic, uses
  `jump_height`), and lava/fire/damaging nodes or water hazards below. `can_jump_cliff` turns a
  gap into a jump.

### Mount helpers
`mcl_mobs.attach/detach/drive/fly` (`mount.lua`) exist for riding and are separate from the above.

---

## 7. Environment

`do_env_damage` (physics.lua:651-850) runs from `step_damage` roughly **once per second**
(`env_damage_timer > 1`, :867) and on mobs of any state except `die`:

1. Resets health-text timer; sets `time_of_day`.
2. Removes the mob outside map limits (:672-676).
3. **Light damage** (:679): `light_damage > 0` and natural light `> 12`: `deal_light_damage`
   (skipped in rain/snow outdoors, :591-601).
4. **Sunlight** (:685-700): `sunlight_damage ~= 0` or `ignited_by_sunlight`; skipped with a
   helmet; ignite sets `mcl_burning.set_on_fire(obj, 10)` unless rain or `group:puts_out_fire`.
5. Computes `standing_in` (node at feet + 0.25), `standing_on`, `standing_under` (eye height)
   (:707-709). Eye height: `head_eye_height` or 90% of the box (default `head_eye_height` is 1 from
   `register_mob`, so mobs without it use 1).
6. `rain_damage`.
7. `get_env_hits` (:604-649): `find_nodes_in_area` over the collisionbox (`base_colbox`) for
   `group:water/lava/fire`, cactus, wither rose. Only the first matching branch applies:
   - `water_damage > 0` and water: `health -= water_damage`.
   - `lava_damage > 0` and lava: `-= lava_damage` (**default 8**), **ignites for 10 s** (even
     `fire_resistant` mobs take the 8; only the burning part is skipped, `mcl_burning.set_on_fire`
     returns for `fire_resistant`).
   - `fire_damage > 0` on `mcl_nether:magma` below: `-= fire_damage`.
   - `fire_damage > 0` and fire: `-= fire_damage`, burns 5 s.
   - `damage_per_second` node at the feet (not lava/fire).
   - cactus: `damage_mob("cactus", 2)`; wither rose: `withering` level 2 for 2 s.
   Each calls `check_for_death(cause, ...)` ("water", "lava", "fire", "dps", "cactus").
8. **Drowning** (:786-818): active when `initial_properties.breath_max ~= -1`: head node
   `drowning > 0` (water has `drowning` set) drains `breath` by 1/s; at 0 takes `drowning`
   damage per second (4 for `breathes_in_water`). Breath regenerates 1/s otherwise. `breath_max =
   -1` means never drowns (kaiju that swim use it).
9. **Suffocation** (:820-847): `suffocation == true` (always) and the feet node is walkable,
   regular box, opaque, without `disable_suffocation`: counter +1 per call; at 3, 2 damage per
   second. Reset otherwise. A big mob whose feet node is inside terrain takes this damage.
10. Returns `check_for_death("unknown", ...)`.

Then `replace_node(pos)` (movement.lua:350-398): sheep eat grass, `replace_what`, ignoring
`child`; skipped entirely if `mobs_griefing` is false (the check is in the replace code,
:386; the `on_replace` callback still runs).

### Burning (`mcl_burning`)
- State lives on the **entity table itself**: `burn_time`, `fire_damage_timer`,
  `collisionbox_cache` (so they are serialized into staticdata, `mcl_burning/init.lua:5-16`,
  `api.lua:3-14`). Attached `mcl_burning:fire` child entity is the visual.
- `set_on_fire(obj, time)` (api.lua:107-160): ignores `fire_resistant` mobs, dead objects
  (`get_hp() < 0`); keeps the larger time if already burning. Players are ignored when
  `enable_damage` is off (load-time).
- `tick(obj, dtime, storage)` (:178-204): reduces `burn_time`; extinguishes at 0, in rain, or when
  touching `group:puts_out_fire`; once per second `mcl_util.deal_damage(obj, 1, {type="on_fire"})`
  unless `fire_damage_resistant`. Mobs get ticked from `step_damage` (physics.lua:853-861)
  unless `fire_resistant`. The globalstep that sets players on fire from `set_on_fire` nodes
  (the globalstep at `mcl_burning/init.lua:25`) does **not** apply to mobs; mobs ignite via `do_env_damage`,
  fire damage, projectiles, fire aspect or `set_on_fire` calls.
- `extinguish(obj)`, `is_burning(obj)` (returns `burn_time`), `is_affected_by_rain`,
  `is_affected_by_sunlight(obj, threshold)` (overworld only).

---

## 8. Griefing and block interaction

| Mechanism | Where | Notes |
|---|---|---|
| `mobs_griefing` setting | `core.settings:get_bool("mobs_griefing") ~= false`, **read once at load** in `mcl_mobs/combat.lua:5`, `movement.lua:13`, `mobs_mc/rover.lua:131`, `snowman.lua:8`, `wither.lua:6`, `ender_dragon.lua:199` | There is **no `mobGriefing` gamerule**; setting (`settingtypes.txt:162`, default true) only. Changing it at runtime does nothing. |
| Explosions | `boom` (combat.lua:460-476) and creeper-type `explode` (:1021-1032) pass `griefing = (mobs_griefing == true)`; `mcl_explosions.explode` also needs its own `mcl_explosions_griefing` setting (`mcl_explosions/init.lua:16,191`, load time). `grief_protected = false` keeps protected nodes safe (:228) | Wither/fireworks call `boom(self, pos, strength, {griefing=false}, true)` to damage without breaking blocks (`wither.lua:51`) |
| `replace_node` | movement.lua:350-398 | Sheep/etc; no node change when `mobs_griefing` false |
| `pathfinding = 2` | combat.lua:155-228 | If no path: builds a dirt-like block (`mcl_mobs.fallback_node`) under itself or digs 2 nodes toward the target and `add_item`s what it removed. **Items are dropped regardless of `mcl_doTileDrops`.** Skips `level`, `unbreakable`, liquid nodes and protected positions |
| Enderman (`mobs_mc:rover`) | rover.lua:199-420 (take/place inside `do_custom`) | Returns early if not griefing. Takes nodes of `group:enderman_takable` within 2 nodes (`find_nodes_in_area_under_air`), skips `is_protected(pos, "")`, `remove_node`, attaches a visual item entity, places it again later with `place_node`. Never drops the node as an item, it carries it |
| Snow golem | snowman.lua:85-110 | Trail of `mcl_core:snow`, only if griefing |
| Wither | wither.lua:23-52 (`wither_unstuck`) | With griefing, digs every node in its box with `_mcl_hardness >= 0` using `dig_node` and then `add_item`s the drops by hand (**unverified**: `dig_node` may already run `handle_node_drops`, which could double the drops). Spawns a wither rose with `place_node` (:444) |
| Ender dragon | ender_dragon.lua:199-225 | Fireball explosion via `boom(self, pos, 2)` |

### No terrain group for natural stone
Mineclonia marks what its cave carver may cut (`overworld_carvable`: stone, granite, andesite,
diorite, deepslate, tuff, mud, muddy mangrove roots). VoxeLibre has no such group:
`mcl_core:stone` has `pickaxey`, `stone`, `building_block`, `material_stone`
(`mcl_core/nodes_base.lua:29`), and `group:stone` also holds stone bricks and the like. Code
that asks "is this natural ground?" has to name the nodes; `vl.lua` does that for
`kaiju_core.is_terrain`.

### Tile drops: `mcl_doTileDrops`
Overrides `minetest.handle_node_drops` (`mcl_item_entity/init.lua:393-420`). `doTileDrops =
get_bool("mcl_doTileDrops", true)` is read **once at load**. The override:
- a creative-mode **digger** gets items into the inventory (no node drops), regardless of the setting;
- `elseif not doTileDrops then return end`: with the setting off nothing drops, **also when
  `digger == nil`** (the "called by hand" case);
- otherwise checks `mcl_autogroup.can_harvest(node, tool, digger)` if there is a digger. Without a
  digger, no tool requirement.
So a kaiju digging with `core.dig_node(pos)` (no digger) drops items if `doTileDrops` is on;
code that calls `core.add_item` itself bypasses the setting.

---

## 9. Spawning

### Registering
- `mcl_mobs:spawn_setup(def)` (spawning.lua:259-307, colon call): requires `def.name` to be a
  **registered entity already** (assert :264). Defaults: `chance 1000`, `aoc 136`, `dimension
  "overworld"`, `interval 1`, `min_height/max_height` overworld bounds, `min_light 0`,
  `max_light 16`, `biomes` -> `biomes_lookup`. A world/`minetest.conf` key named like the mob
  (`mobs_mc:foo = chance,aoc`) overrides `chance`/`aoc`; `chance 0` disables (:276-288).
  `type_of_spawning` is `"ground"`, `"water"` or `"lava"` (the code's default string
  `"overworld"` matches none of the checks).
- `mcl_mobs:spawn_specific(...)` (:375) is the deprecated wrapper. `non_spawn_specific` (:361)
  records light levels for mobs that do not spawn naturally (used by spawner eggs).
- There is no spawn code in `register_mob`. **A mod that registers a mob and nothing else will
  never see it spawn naturally.**
- `mcl_mobs:spawn_abm_check` (:230) is a no-op hook.

### The natural spawn loop
`core.register_globalstep` (spawning.lua:1209-1227) runs `attempt_spawn` in fixed timeslices
(500 us "easy" budget). It is skipped when **`gamerule:doMobSpawning`** is off. That gamerule's
default is the setting `mobs_spawn` (`spawning.lua:102-109`; `settingtypes.txt:142`, default
true) and can be changed at runtime with `/gamerule doMobSpawning` (`vl_tuning`). Per attempt
and player: pick a position 24-128 nodes away (`MOB_SPAWN_ZONE_INNER/OUTER`, :60-63; biased close,
:394-466), skip protected positions unless `mobs_spawn_protected` is explicitly false (`~= false`, :111,
used :829 and :1066), build a state (light, biome, dimension), pick a mob by
the spawn dictionary and caps, `spawn_check` (:600-611: `initial_spawn_check`, height, then
`check_position`), `can_spawn(pos)` (:1100-1108), and group spawn (`spawn_in_group` default 4,
`group_roll_probability` 0.95 per extra mob). Caps (settings `mcl_mob_cap_*`, :75-86): hostile
70, animal 10, ambient 15, water 8, per-player 75, total 500, and so on.
`only_peaceful_mobs` removes `type == "monster"` mobs on activation (api.lua:117-122) and refuses
eggs for them.
Spawn state also needs `mobs_mc` `spawn_class` to match the cap categories.

### `mcl_mobs.spawn(pos, id, opts)` (spawning.lua:626-713)
The programmatic API. `id` may be a bare name: tries `id`, `"mobs_mc:"..id`, `"extra_mobs:"..id`.
- Requires the entity def to have `is_mob` (set in `final_def`, :301).
- Unless `opts.force`: runs `can_spawn(pos)` and `has_room` (collisionbox/`spawnbox` volume must
  be free of walkable nodes; a 2-wide mob gets one retry with a half-node shift).
- Integer `pos.y` is treated as a node: `pos.y - 0.495 - collisionbox[2]` (spawn just above
  ground).
- `core.add_entity(pos, name)`; then initialises the head bone if `head_swivel`.
- Returns the **ObjectRef** (not the luaentity), or `false`.
- Natural spawns use `force = false`; eggs use `force = true` (no room check).

### Eggs (`register_egg`, init.lua:740-775)
`mcl_mobs.register_egg(mob_id, desc, bg_color, overlay_color, addegg, no_creative)`:
- Registers a `craftitem` **with the same name as the entity** (`mob_id`), group `spawn_egg=1`
  (and `not_in_creative_inventory` with `no_creative`). The item and entity share a namespace
  without conflict, but you cannot reuse the name for another item.
- Icon: `(spawn_egg.png^[multiply:bg)^(spawn_egg_overlay.png^[multiply:overlay)`; with
  `mcl_old_spawn_icons` uses `mobs_mc_spawn_icon_<name>.png` if present. `addegg == 1` composes with
  the chicken egg texture. `compat.lua` accepts the old `mcl_mobs:register_egg` colon call.
- `on_place_egg` (:635-727): `handle_node_rightclick` first; within map limits; not protected;
  target node not opaque; on a mob spawner node configures it (needs `maphack`); refuses
  `type == "monster"` mobs with `only_peaceful_mobs`; `mcl_mobs.spawn(pos, mobname, {force=true})`;
  non-monsters spawn **tamed to the placer** unless sneaking (`owner`, `tamed`); egg metadata
  `name` becomes the nametag (30 chars). Takes one egg unless creative.

### Conversions
`mcl_mobs.register_conversion(old, new)` (init.lua:431): registers an entity that replaces itself
by `new` on activation (strips `mesh`, `textures`, `base_*` from staticdata, `STRIP_FIELDS` :423).

---

## 10. Staticdata and `on_activate`

### `get_staticdata` (`api.lua:67-111`)
1. Removes particle spawners of connected players.
2. Would return `"remove"` for far, despawnable mobs with `lifetimer <= 20` (:73-77), but see the
   missing `return` in `despawn_allowed` (§3): in practice this never triggers.
3. **Mutates the live entity**: `attack = nil`, `following = nil`, `state = "stand"` (:80-82).
   This runs on every save, also for loaded, active mobs (autosave, shutdown).
4. Serializes **every field of `self` that is not a function, nil, or userdata** (except
   `_cmi_components`) with `minetest.serialize`. This includes tables (`path`, `waypoints`,
   `acc`, `drops`, `armor`, `animation`, `sounds`, anything you stored). Tables containing
   ObjectRefs break serialization; drop them yourself first.
5. `_mcl_potions` is saved, calling each effect's `on_save_effect` first (:95-103).

### `mob_activate` (`api.lua:113-295`)
1. Removes the mob if `staticdata == "remove"`, or `type == "monster"` with `only_peaceful_mobs`.
2. `tmp = deserialize(staticdata)`; if `tmp.base_mesh` differs from the registered mesh,
   `strip_staticdata` first (:128). **Then `for k, v in pairs(tmp) do self[k] = v end` (:130):
   every saved field overwrites the entity, including def-derived fields** (`armor`, `damage`,
   `view_range`, `drops`, `walk_velocity`, `reach`, ...). Changing those in a new definition
   version has **no effect on already saved mobs** (new spawns only). `base_colbox`, `base_selbox`,
   `base_size`, `base_texture`, `texture_selected` are persisted and re-applied.
3. `self._removed` -> remove (a dead mob saved mid-`die` was marked removed by `remove_entity`).
4. Validates textures/colbox/selbox/size/mesh, recreates them from `def` if missing.
5. `health == 0` -> random `hp_min..hp_max`; `breath` default `breath_max`. (A saved health
   `<= 0` that is not exactly 0 stays; the first step then runs `check_for_death` again.)
6. Resets `self.path` (`way`, `lastpos`, `stuck`, `following`, `stuck_timer`, `los_switcher`,
   `height_switcher`, `last_seen_target_pos`) (:219-228).
7. Sets armor groups, `old_y`, `old_health`, resets `standing_in/on` to `"ignore"`, `timer`,
   `fuse`, `force_attack`, `texture_mods`, `blinktimer`.
8. **`self.object:set_properties(self)`** (:266): the entity table itself is used as a properties
   table, so any field whose name is an engine property (`mesh`, `textures`, `nametag`, `glow`,
   `visual_size`, `collisionbox`, `physical`, `pointable`, ...) takes effect. The FIXME there
   says as much.
9. Random yaw, `update_tag`, animation `stand`.
10. `riden_by_jock` -> removed. `on_spawn` once (`on_spawn_run`). `armor_list` init for
    `wears_armor`. `_mcl_potions` reloaded (`mcl_potions._load_entity_effects`).
11. `after_activate(self, staticdata, def, dtime)` (:289).

`on_activate` first forces `collide_with_objects = false` (init.lua:382-390) because engine mob
collisions are replaced by `collision()`.

`lifetimer` is saved too. `xp_timestamp` is reset to 0 on activate (:293).

---

## 11. Projectiles (`vl_projectile`)

Doc: `ITEMS/vl_projectile/api.md`. Code: `ITEMS/vl_projectile/init.lua`.

- `vl_projectile.register(name, def)` (:655): requires `def._vl_projectile.behaviors` (list of
  functions); sets `on_step = update_projectile` if absent; clears `_thrower/_shooter/_last_pos`.
  If `has_owner_grace_distance` is in the behaviours, `allow_punching` additionally requires
  `self._allow_punch` (owner must be 1.5 nodes away).
- `vl_projectile.create(id, {pos, dir, velocity, drag, owner|owner_id, staticdata, extra})` (:622):
  adds the entity, applies physics, sets `_owner` (via `mcl_util.get_entity_id`: a player name, or
  a generated uuid stored on the owning entity), `_startpos`, `_starting_velocity`.
- `update_projectile(self, dtime)` (:62-107): timer vs `maximum_time` (default 300 s), runs
  `behaviors`; stops at the first that returns true; then physics (gravity unless
  `ignore_gravity`, `liquid_drag`, rotation to face velocity).
- Behaviours: `burns` (:209), `has_owner_grace_distance` (:226), `has_tracer` (:234), `sticks` (:352),
  `collides_with_solids` (:364), `collides_with_entities` (:578), `raycast_collides_with_entities`
  (:596). A projectile defined without behaviours asserts (:661).

### Hit checks
- **`collides_with_entities`** (:578-594): `get_objects_inside_radius(pos, 1.5)`; the first object
  that is a **player** (always, there is **no `enable_pvp` test here**) or a mob/entity with
  `is_mob` or `_hittable_by_projectile`. Skips itself and entities of the same projectile name.
- **`raycast_collides_with_entities`** (:596-620): raycast `pos .. pos + vel*0.1`; candidates pass
  `check_hitpoint` (:143-160): **players only if `enable_pvp`** (the setting is read once at load,
  :11, with `get_bool("enable_pvp")` and no default argument), else `is_mob` or
  `_hittable_by_projectile` entities. Closest wins.
- `handle_entity_collision` (:478-575):
  - `allow_punching` (:483) is `projectile_def.allow_punching or true`, so a literal `false` does
    **not** disable punching; only a function returning false does.
  - Entity hook `object._vl_projectile.can_punch(object, projectile)` can veto.
  - Damage only for players when `damages_players`, or for mobs/`_hittable_by_projectile`.
    Applies via `object:punch(projectile_obj, 1.0, projectile_def.tool or {full_punch_interval=1.0,
    damage_groups=dmg}, dir)`, `damage_groups` may be a function. So on a mob this goes through
    `on_punch`: **armor groups, the 0.5 s invulnerability and knockback apply**.
  - Burning projectiles ignite the target 5 s; shields (`mcl_shields.is_blocking`) stop it.
  - `on_collide_with_entity`, then the target's `_vl_projectile.on_collide`; removed unless
    `survive_collision`.
- Solids: `collides_with_solids` (:364-476) removes the projectile (or sticks it with `sticks`),
  calling `on_collide_with_solid` and the node's `_vl_projectile.on_collide`.

### `mcl_mobs.register_arrow` / mob shooting
`mcl_mobs.register_arrow(name, def)` (init.lua:463-598) is the old API on top of `vl_projectile`:
behaviours are `has_owner_grace_distance`, plus `collides_with_solids` if `hit_node`, plus
`collides_with_entities` if `hit_player`/`hit_mob`/`hit_object` (so **no `enable_pvp` gate and
players are hit regardless**, `damages_players = true`). `_lifetime` is in **seconds** (default 7),
`velocity`, `homing`, `drop`, `tail*`, `timer`, `switch` fields as before. `hit_player(self,
player)`, `hit_mob(self, mob)` (only if `mob.is_mob`), `hit_object` for any other entity.
Collisions with the owner in the first 2 s are ignored. A punched arrow is reflected and its
owner becomes the puncher. `mcl_mobs.get_arrow_damage_func(damage, type)` (:455) returns a
`hit` function that calls `mcl_util.deal_damage(object, damage, {type=type})` (no `source`, so
no retaliation).
A shooting mob creates the arrow with `vl_projectile.create(self.arrow, {pos, owner=self})`,
sets `ent._shooter`, `_saved_shooter_pos` and, for `homing`, `_target` (combat.lua:1190-1207).

---

## 12. Status effects (`mcl_potions`)

API (documented in `ITEMS/mcl_potions/API.md`):

| Function | Notes |
|---|---|
| `give_effect(name, obj, factor, duration, no_particles)` (functions.lua:1805) | `duration = "INF"` for infinite. Returns false if the effect is unknown or the target invalid |
| `give_effect_by_level(name, obj, level, duration, no_particles)` (:1846) | `level 0` returns false; effects without factors ignore level |
| `has_effect(obj, name)` (:1551), `get_effect(obj, name)` (:1558, returns `{dur, timer, factor, ...}`), `get_effect_level` (:1565) | `get_effect` returns `false` when absent |
| `clear_effect(obj, name)` (:1598) | calls `on_end`/`after_end` |
| `register_effect(def)` (:118) | `name`, `description`, `get_tt`, `res_condition`, `on_start`, `on_load`, `on_step`, `on_hit_timer`, `on_end`, `on_save_effect`, `particle_color`, `uses_factor`, `lvl1_factor`, `lvl2_factor`, `timer_uses_factor` or `hit_timer_step`, `damage_modifier`. Reserved names: `list`, `heal`, `remove`, `clear` |
| `register_generic_resistance_predicate(fn(obj, name))` (:1778) | Return true to make the object resist an effect |

### Valid targets
`target_valid` (:1782-1803): `get_hp() > 0`; players, or entities that have **`_mcl_potions`**
(all `register_mob` mobs) and are **not `is_boss`**; no registered resistance predicate and no
effect `res_condition` returns true. State is held in `EF[name][object]`, saved/loaded for mobs
through `_mcl_potions` in staticdata (`_load_entity_effects`, :1530).

### Effect names (all registered in `mcl_potions/functions.lua`)
`invisibility`, `poison`, `regeneration`, `strength`, `weakness`, `water_breathing`,
`dolphin_grace`, `leaping`, `slow_falling`, `swiftness`, `slowness`, `levitation`,
`night_vision`, `darkness`, `glowing`, `health_boost`, `absorption`, `fire_resistance`,
`resistance`, `luck`, `bad_luck`, `bad_omen`, `hero_of_village`, `withering`, `frost`,
`blindness`, `nausea`, `food_poisoning`, `saturation`, `haste`, `fatigue`, `conduit_power`.
(Line of each `register_effect` call: 195, 214, 236, 261, 273, 299, 317, 341, 363, 387, 408, 429,
447, 477, 534, 593, 620, 662, 676, 695, 714, 733, 743, 749, 771, 824, 867, 916, 943, 1008, 1029,
1050.)

### What works on mobs
Each effect has a `res_condition`; for most it is `not object:is_player()` with a TODO ("needs
mob physics factor API"). Effects that **do apply to mobs**:
- `poison` (1 dmg per tick via `deal_damage(.., {type="magic"})`, never lethal; spiders and
  `harmed_by_heal` mobs resist), `regeneration` (+1 HP; `harmed_by_heal` mobs resist),
  `withering` (except mobs with "wither" in the name), `strength`, `weakness` (used when the
  mob is the hitter, e.g. `on_punch` reads the hitter's effects), `invisibility`, `levitation`,
  `glowing`, `bad_omen`, `hero_of_village`.
- **No effect on mobs** (resisted): `slowness`, `swiftness`, `leaping`, `slow_falling`, `frost`,
  `dolphin_grace`, `water_breathing`, `night_vision`, `darkness`, `blindness`, `nausea`,
  `food_poisoning`, `saturation`, `health_boost`, `absorption`, `fire_resistance`, `resistance`,
  `luck`, `bad_luck`, `haste`, `fatigue`, `conduit_power`. `give_effect` returns false.
  There is therefore **no way to slow a mob with potions**; `bane_of_arthropods` slowness is
  also a no-op.
- `mcl_potions.healing_func(obj, hp)` (:1859) heals mobs or hurts `harmed_by_heal` mobs.
- Wither roses (`withering`, level 2, 2 s) and `dealt_effect` on melee attackers use
  `give_effect_by_level`.

---

## 13. Pitfalls for mod authors

1. **Def fields are a whitelist** (§2). Anything not copied is gone: custom `_fields`,
   `on_step`, `on_punch`, `on_deactivate`, `initial_properties.mesh`. Put extra state in
   `on_spawn`/`after_activate`, behaviour in `do_custom`/`do_punch`/`on_die`/`attack_state`, or
   copy fields onto the entity after `register_mob` (what `vl.lua` does, with `rawget`).
2. **Metatable `__index` shadowing.** Entities resolve missing keys through `final_def` and then
   `mob_class` (`init.lua:419`). A field you forgot to copy, or `nil` by design, can be silently
   answered by a **method of the same name** (e.g. `stand`, `flop`, `teleport`, `collision`,
   `gopath`). `self.foo == nil` checks are unreliable; use `rawget(self, "foo")` when a name may
   collide.
3. **`or true` / `or 1` / `or 8`** defaults (§2): `pushable`, `suffocation`, `lava_damage`...
   cannot be switched off by `false`.
4. **Settings read at load time**: `mobs_griefing` (six files), `enable_damage` (combat.lua:3,
   mcl_burning/api.lua:1), `enable_pvp` (vl_projectile:11), `mcl_doTileDrops`
   (mcl_item_entity:393), `mcl_explosions_griefing`, `mobs_drop_items`, `mcl_mob_active_range`,
   `mcl_mobs_open_gates`, `mobs_debug`. A mod cannot toggle these after load by changing
   `core.settings`; only gamerules (`vl_tuning`: `doMobSpawning`, `doMobLoot`,
   `maxEntityCramming`) are live. Tests that flip griefing at runtime need to restart or patch
   the cached local (not reachable) or avoid VoxeLibre's code path.
5. **Staticdata overrides the definition** (§10): saved mobs keep old `armor`, `damage`,
   `drops`, `view_range`. Old saves also carry `path`, `waypoints`, `acc`. `get_staticdata`
   resets `state`/`attack` on the live entity at every save.
6. **`health`, not `get_hp()`** (§5): `obj:get_hp()` never changes for mobs (armor group
   `immortal`); use `mcl_util.get_hp` or `self.health`. `do_states_attack` stops attacking a
   *mob* target when `get_hp() <= 0` (engine value).
7. **Armor groups gate punch damage**: a damage group missing from the mob's armor table deals 0
   (`on_punch`); `mcl_util.deal_damage` bypasses it. `damage_mob` floors, so `< 1` does nothing.
   Direct `health` edits skip effects, XP flag (`xp_timestamp`), and `on_die` until the next step.
8. **`do_custom` and any other step code runs inside `pcall`**; errors are logged, not raised
   (§3). Return `false` from `do_custom` to suppress `do_states`; return nothing to keep the
   default AI.
9. **Mobs are frozen when no player is within 48 nodes** (`mcl_mob_active_range`) for movement
   (step 9), but `do_custom`, `do_states` timers and the damage/despawn code still run. Test
   fixtures that put a mob far from a player see no movement.
10. **`set_velocity` is an acceleration** and does nothing airborne for non-`fly` mobs (§3). Code
    that calls `object:set_velocity` directly is overridden by the 0.7 damping and by
    `falling`'s acceleration unless it sets `fly`.
11. **`gopath` clears `order` and sets `order = "stand"` on arrival** (pathfinding.lua:182,
    :425); mobs then stand still and stop jumping until `order` is reset.
12. **`mob_class:despawn_allowed()` has no return** (spawning.lua:1241-1243): do not rely on
    it; check `can_despawn`, `tamed`, `persistent`, `nametag` yourself.
13. **Looting is dead code**, `smart_mobs` LOS is always false, `monster_attack` leaks `type`
    and `name` between loop iterations (§4, §5): do not build on these.
14. **`state == "die"` is the only dead marker**; there is no `dead` field. A mob stays a valid
    entity for 0.5-1.5+ s (more with a long `die` animation) and keeps being a target
    candidate for others unless they check `state`. `instant_death` skips the animation.
15. **`mcl_mobs.spawn` returns an ObjectRef**; `get_luaentity()` for the entity. `pos.y` that is
    an integer is lowered by 0.495 - `collisionbox[2]`.
16. **Spawn egg name = entity name.** Entities spawned from eggs of a non-monster become tamed to
    the placer unless sneaking.
17. **`collide_with_objects = false`** is forced in `on_activate`; mob-mob pushing is done by
    `collision()` only when `pushable` (always) and via `set_velocity`.
18. **Handlers that call `mcl_mobs.register_arrow`** get `collides_with_entities`
    (radius 1.5, players always hit). Only the raycast behaviour obeys `enable_pvp`.
19. **`mcl_burning` stores burn state on the entity table**, so it persists in staticdata; a
    mob saved while burning resumes burning on load.
20. **The `is_boss` flag exempts mobs from every potion effect** (`target_valid`).

---

## 14. Mineclonia differences (short)

Full API comparison table: [`../README.md#api-comparison`](../README.md#api-comparison); layer
description: [`README.md` §7](README.md). Summary of the structural gaps the layer bridges:

| Area | Mineclonia | VoxeLibre 0.92.4 |
|---|---|---|
| Registration | Keeps every def field (methods, `_fields`) | Whitelist (§2) |
| AI loop | `run_ai`, `ai_functions`, target rules (`_targeting_rules`), alert receiver | `do_states` state machine, `monster_attack`, `specific_attack` lists (§3-4) |
| Pathfinding | Own pathfinder (`waypoints`, `pathfinding_context`, `gopath(target, bonus)`, penalties), body-aware | `core.find_path`, 1-wide; `gopath(target, callback, prioritised)` and `smart_mobs` (§6) |
| Motion | `motion_step` physics, `_moveresult` | `acc` plus damping, `falling` (§3, §6) |
| Environment | `check_standin`, `_immersion_depth`, drowning/fall/env steps | `standing_in`, once-per-second `do_env_damage` (§7) |
| Damage | `receive_damage`, `dead` flag, `check_for_death(reason, damage)` | `on_punch`/`damage_mob`/`deal_damage`; `state == "die"`; floored damage (§5) |
| Knockback | `knockback_resistance`, `projectile_knockback` | `knock_back` boolean, `kb` formula in `on_punch` |
| Griefing/drops | Gamerules `mobs_griefing`, `doTileDrops` (`mobs_mc.is_mob_griefing_enabled`, `mcl_vars.do_tile_drops`) | Load-time settings `mobs_griefing`, `mcl_doTileDrops` (§8) |
| Projectiles | `_lifetime` in steps; arrow damage func with source | `vl_projectile`, `_lifetime` in seconds, `enable_pvp` gate in raycast check only (§11) |
| Potions | Same API | Same API; mobs resist most effects (§12) |
| Spawning | Same shape (`spawn_setup`, `register_egg`) | §9; egg uses `force = true` |
| Naming | `mobs_mc:enderman`, creeper | `mobs_mc:rover`, `mobs_mc:stalker` |
