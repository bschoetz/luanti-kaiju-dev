# Kaiju

Giant monsters for the [Mineclonia](https://codeberg.org/mineclonia/mineclonia) and
[VoxeLibre](https://content.luanti.org/packages/wuzzy/mineclone2/) (formerly MineClone2) games on
[Luanti](https://www.luanti.org/) 5.10 or newer. One modpack, four kaiju:

| Kaiju | Mod | What it is |
|---|---|---|
| **Gojira** | [`gojira/`](gojira/README.md) | A 15-node fire-breathing kaiju. Hunts players, smashes through forests, houses and hills, wades through lakes. 500 HP. |
| **Mothra** | [`mothra/`](mothra/README.md) | A giant guardian moth with a 26-node wingspan. Neutral to players; hunts Ghidorah, Gojira and monsters from the air with wing gusts and poison powder. 350 HP. |
| **King Ghidorah** | [`ghidorah/`](ghidorah/README.md) | A three-headed golden dragon, about 20 nodes tall, that walks and flies. Gravity beams from every head; a severed head grows back. 600 HP. |

| **Cthulhu** | [`cthulhu/`](cthulhu/README.md) | A 13-node amphibious sea monster. Sleeps on the sea floor, neutral until someone comes within 48 nodes of his home; then he rises, grabs players and small mobs and holds them under water, and clouds the minds of players near him. Heals in the sea, weak on land. 550 HP. |

The fifth mod, [`kaiju_core/`](kaiju_core/README.md), is the library the four share
(block smashing, bulldozing, wading, flight). It adds nothing to the game by itself.

Gojira and Mothra both go for Ghidorah first; without him, Mothra hunts Gojira. When a
Ghidorah dies, the Gojiras and Mothras around him call a truce: each species moves 150
nodes away, in opposite directions, and ignores every target on the way, unless it is
attacked or another Ghidorah appears.

Cthulhu stands apart. He attacks whoever enters his territory, kaiju included, but not
those on a truce retreat. Gojira and Ghidorah fight him when he attacks them or comes
within 32 nodes; Mothra only while he is after someone. Under water nobody can target him.

## Install

1. Copy this folder (`kaiju/`, the one that contains `modpack.conf`) into your mods folder,
   so that you get `~/.minetest/mods/kaiju/modpack.conf` (`~/.luanti/mods/` on newer
   installs).
2. In Luanti's main menu: select a Mineclonia or VoxeLibre world, **Select Mods**, enable the modpack
   **Kaiju** (this enables all five mods), **Save**.
3. In the game, spawn the kaiju with their spawn eggs from the creative inventory, or
   `/giveme gojira:gojira`, `/giveme mothra:mothra`, `/giveme ghidorah:ghidorah`,
   `/giveme cthulhu:cthulhu`. They never spawn naturally. Use Cthulhu's egg at the sea: he
   makes the nearest deep water (15 nodes or more, within 48 nodes) his home.

## Upgrade from the four separate mods

Before this modpack existed, `kaiju_core`, `gojira`, `mothra` and `ghidorah` were four
folders directly in the mods folder. The mod, entity and item names have not changed, so
existing worlds keep their kaiju and eggs. Do the steps in this order, **with Luanti
closed, and do step 3 before you start the world again**:

1. Delete the four old folders. Left in place, they clash with the modpack (duplicate mod
   names):
   ```sh
   cd ~/.minetest/mods && rm -r kaiju_core gojira mothra ghidorah
   ```
2. Copy the `kaiju/` folder in, as under Install.
3. For **every** world that had the kaiju enabled, point the world at the new location.
   Either in the main menu (select the world, **Select Mods**, enable **Kaiju**, **Save**),
   or in the world's `world.mt`:
   ```sh
   sed -i -E 's#^(load_mod_(kaiju_core|gojira|mothra|ghidorah)) = mods/(kaiju/)?#\1 = mods/kaiju/#' \
       ~/.minetest/worlds/<world>/world.mt
   ```
   The four lines must read `load_mod_gojira = mods/kaiju/gojira` and so on. Cthulhu did
   not exist in the old layout: enable him in the main menu, or add
   `load_mod_cthulhu = mods/kaiju/cthulhu`.

Why step 3 matters: `world.mt` stores each enabled mod with its path (`mods/gojira`). After
the move that path is gone, and Luanti starts the world **without** the kaiju mods. It only
logs `ERROR[ServerStart]: The following mods could not be found`. Kaiju in the loaded area
are then unknown entities without their code: they drift off or sink into the ground, and
some are gone when the mods are back. Eggs in inventories are kept. `tests/compat.sh` in
the source repository runs both cases.

## Settings

In the main menu under Settings → Content: Mods → Kaiju, or in `minetest.conf`. They take
effect at once, also with `/set` in a running game.

| Setting | Default | Off means |
|---|---|---|
| `kaiju_smash_blocks` | `true` | Gojira, Ghidorah and Cthulhu no longer break the blocks in their way, sweep them away with their tails or flatten their landing spot. They then get stuck in forests and towns. |
| `kaiju_gojira_fire` | `true` | Gojira's fire breath no longer sets blocks on fire. It still burns whoever it hits. |
| `kaiju_ghidorah_beam_blasts` | `true` | Ghidorah's beams no longer blast craters. They still hurt whoever they hit. |

All three work on top of the game's mob griefing switch: Mineclonia's `mobs_griefing`
gamerule (`/gamerule mobs_griefing false`), VoxeLibre's `mobs_griefing` setting. Off, nothing
is destroyed, whatever is set here. Protected
areas are never touched. The defaults are the behaviour the mods had before the settings
existed.

## Supported games

| Game | Version tested | Status |
|---|---|---|
| Mineclonia | the `vendor/` checkout and the ContentDB release | The game the kaiju are written for: they use its `mcl_mobs` AI hooks directly. |
| VoxeLibre (game id `mineclone2`) | 0.92.4 | Supported through a compatibility layer in `kaiju_core` (`vl.lua`), with the limitations below. |

### VoxeLibre

VoxeLibre's `mcl_mobs` is the older ancestor of the one Mineclonia rewrote. The kaiju are
written against Mineclonia's AI hooks (`run_ai`, `ai_functions`, `_targeting_rules`,
`attack_melee`, `motion_step`, navigation, `receive_damage`, ...), and VoxeLibre has none of
them: its mobs run a fixed state machine (`do_states`) instead. So `kaiju_core` checks which
`mcl_mobs` it got (Mineclonia's has `mob_class.run_ai`) and on VoxeLibre loads `vl.lua`, a
small mob class of its own on top of VoxeLibre's that provides the Mineclonia hooks the kaiju
use. The kaiju mods take `mcl_mobs` from `kaiju_core.mcl_mobs`, which on Mineclonia *is*
Mineclonia's `mcl_mobs`: nothing changes there.

What works on VoxeLibre: spawn eggs; all five mods load; each kaiju moves, targets, fights,
dies (die clip, drops, XP) and is saved with the world. Gojira breathes fire, smashes and
bulldozes, wades and swims; Mothra flies, gusts and dusts; Ghidorah walks, flies, fires
beams, loses and regrows heads; Cthulhu sleeps, defends his territory, swims in sea mode,
grabs, and has his aura; hit boxes, arrows and the truce work. The balance is close to
Mineclonia's (`tests/README.md` has the numbers).

Limitations on VoxeLibre:

- **No pathfinder.** VoxeLibre's has another interface; the kaiju walk straight at their
  target or goal. They smash through what is in the way, as on Mineclonia; with
  `kaiju_smash_blocks` off they get stuck sooner. They jump against a 2-node wall.
- **Simpler walking physics** (gravity, a fixed walking speed, braking in water, pushing
  out of other mobs), tuned so that Gojira's speeds match Mineclonia's (about 6 nodes/s on
  land, 5 swimming). Punches cause no knockback.
- **No environmental damage except burning**: lava, fire nodes, suffocation, drowning and
  fall damage don't hurt the kaiju (on Mineclonia they are fire resistant or switch most of
  this off anyway).
- **No alerts**: Gojira's last targeting rule (mobs alerting others of their kind) never
  fires, as VoxeLibre's mobs send no such alerts.
- **Griefing** follows VoxeLibre's `mobs_griefing` setting for all kaiju (Mineclonia: a
  gamerule per mob), and the 5 % block drops follow `mcl_doTileDrops`.
- VoxeLibre has no ghast hurt sound: Ghidorah uses the enderman's.

#### API comparison

Every external API the kaiju use, Mineclonia (vendor checkout) against VoxeLibre 0.92.4.
"Layer" means `kaiju_core/vl.lua` provides it on VoxeLibre.

| API | Mineclonia | VoxeLibre 0.92.4 | On VoxeLibre |
|---|---|---|---|
| `mcl_mobs.register_mob(name, def)` | keeps every field of `def` (methods and `_fields` included) | copies a fixed list of fields; requires `spawn_class`; HP in `initial_properties` | layer: registers, then copies the remaining fields, puts its class under the entity, sets `spawn_class`, `can_despawn = false` and `initial_properties` (boxes, size, HP) |
| `_targeting_rules`, `build_nearest_target_rule`, `build_retaliation_target_rule`, `build_alert_receiver_rule`, `build_target_rule` | yes | no (`monster_attack`, `specific_attack`, `do_attack`) | layer: own implementation; no `alert_others`; the alert receiver rule never fires |
| `run_ai`, `ai_functions`, `ai_step`, `check_attack`, `get_active_target`, `attack_end`, `check_pace`, `check_timer` | yes | no (`do_states` state machine) | layer |
| `attack_null`, `attack_melee`, `pre_melee_attack`, `custom_attack`, `melee_interval`, `_melee_esp` | yes | `attack_type` dogfight/shoot/explode | layer: Mineclonia's melee (walk at the target, bite in reach and in sight) |
| `check_standin`, `_immersion_depth`, `_liquidtype` | yes | no (`standing_in`) | layer: water depth above the feet |
| `motion_step`, `_moveresult` | yes | no (physics in `on_step`, `self.acc`, `falling`) | layer: walking physics; the kaiju's own flight and sea motion run unchanged |
| `waypoints`, `pathfinding_context`, `cancel_navigation`, `go_to_stupidly`, `is_navigating`, `navigation_finished`, `gopath(target, bonus)`, `gwp_penalties` | yes (pathfinder) | `gopath(target, callback, prioritised)` with its own state | layer: straight lines; `waypoints` and `pathfinding_context` stay `nil` |
| Mobs pushing each other apart (`pushable`) | yes, in its physics | in its `on_step` (`collision`, not run here); `pushable` always true | layer: overlapping kaiju push each other apart at 3 nodes/s (Mothra not: `pushable = false`); small mobs don't push them |
| `halt_in_tracks`, `look_at`, `set_yaw` | yes | `set_yaw(yaw, delay)` only | layer (turns at 5 rad/s) |
| `receive_damage`, `mcl_util.deal_damage` on a mob | `deal_damage` → `receive_damage` | `deal_damage` → the entity's `deal_damage` or `damage_mob` | layer: `on_punch`, `deal_damage` and `damage_mob` all end in `receive_damage` (attacker, retaliation) |
| `check_for_death(reason, damage)`, `on_die`, `dead` | yes | `check_for_death(cause, cmi_cause, info)` by `old_health`; `state = "die"` | layer: Mineclonia's signature around VoxeLibre's (flash, sounds, drops, XP, die clip, removal), sets `dead` |
| `heal_mob` | yes | no | layer |
| `valid_enemy`, `test_object_and_restriction`, `attack_player_allowed` | yes | no | layer: creative and `only_peaceful_mobs` protect players; a dying VoxeLibre mob (`state == "die"`) is no target |
| `set_animation` (punch override, `_current_animation`), `set_animation_speed` | walk at `walk_speed` × speed | no punch override; walk scaled by `run_velocity` | layer: Mineclonia's rules |
| `mob_sound`, `sounds.base_pitch`, `sounds.distance` | yes | yes (with a cool-off) | layer: without the cool-off |
| `post_load_staticdata`, staticdata | ObjectRefs dropped at the top level | the same, but `get_staticdata` also clears `attack` and `state` | layer: keeps them; calls `post_load_staticdata` on activation |
| `mcl_mobs.register_egg` | yes | yes, same signature; places with `force` (no room check) | unchanged |
| `mcl_mobs.register_arrow`, `_lifetime`, `hit_mob`, `_shooter` | `_lifetime` in steps | on `vl_projectile`: `_lifetime` in seconds, hits within 1.5 nodes, `hit_object` for other entities | layer: converts the lifetime, raycasts along the path (then the stock check, which also finds players without `enable_pvp`), passes hit-box hits to the kaiju, never hits the shooter |
| `mcl_mobs.get_arrow_damage_func(damage, type, shooter)` | with source | without source | layer: with source (retaliation) |
| `knockback_resistance`, `knock_back`, `projectile_knockback` | yes | `knock_back` | the layer's `on_punch` has no knockback |
| `step_drowning`, fall damage, environment damage | yes | `do_env_damage`, `falling` | not run (see limitations); `mcl_burning.tick` is |
| `mobs_mc.is_mob_griefing_enabled` (gamerule `mobs_griefing`) | yes | no; setting `mobs_griefing` | `kaiju_core.mob_griefing` |
| `mcl_vars.do_tile_drops` (gamerule `doTileDrops`) | yes | no; setting `mcl_doTileDrops` | `kaiju_core.tile_drops` |
| `mcl_util.deal_damage` | yes | yes | unchanged |
| `mcl_potions.give_effect_by_level`, `get_effect` (`dur`, `timer`), `has_effect`; poison, nausea, darkness | yes | yes, same | unchanged |
| `mcl_burning.set_on_fire`, `mcl_burning.tick` | yes | yes | unchanged |
| `mcl_fire:fire` | yes | yes | unchanged |
| `mcl_explosions.explode(pos, strength, info, puncher)` | yes | `(pos, strength, info, direct, source)`, spares `direct` | unchanged |
| `mcl_init` (`mcl_vars`) | yes | yes | unchanged |
| Mob names in rules: `mobs_mc:iron_golem`, `bat`, `blaze`, `vex`, `ghast` | yes | yes | unchanged |
| Mob fields read on other mobs: `is_mob`, `type`, `dead`, `collisionbox`, `swims`, `breathes_in_water` | yes | `dead` and `collisionbox` missing | `dead` → `state == "die"` in the layer's target checks; Cthulhu falls back to the object's collision box |
| Sounds `mobs_mc_*` (bear, wither, ender dragon, parrot, vex, guardian, squid) | yes | yes, except `mobs_mc_ghast_hurt` | layer: replaced by `mobs_mc_enderman_hurt` |
| Textures `fire_basic_flame`, `mcl_particles_*`, `spawn_egg*` | yes | yes | unchanged |
| Nodes: group `water`, `mcl_core:water_source`, `mcl_fire:fire`; drops `mcl_core:diamond`, `mcl_mobitems:*`, `mcl_ocean:prismarine_crystals`, `mcl_nether:glowstone_dust` | yes | yes | unchanged |
| `mcl_core:goldblock` (Ghidorah's drop; it used to say `gold_block`, which neither game has) | yes | yes | fixed for both games |
| `mcl_boats` driver field `_driver` | yes | yes | unchanged |
| `mod.conf` depends: `mcl_mobs`, `mobs_mc`, `mcl_init`, `mcl_util`, `mcl_potions`, `mcl_burning`, `mcl_fire`, `mcl_explosions` | yes | yes, all | unchanged |

## More

- Stats, behaviour, model pipeline and known limitations: the README of each mod, linked
  in the table above.
- Source repository layout, model generators and the test harness: `README.md`, `tools/`
  and `tests/` one level above this folder (not needed to play).

## License

MIT, for the code and the media (models, textures): see the `LICENSE` file of the
repository. The sounds are Mineclonia's and VoxeLibre's own, used by name; nothing of
Mineclonia or VoxeLibre is copied into this folder.
