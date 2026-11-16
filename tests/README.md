# Kaiju test harness

These are end-to-end tests for the `kaiju` modpack (`../kaiju/`): the `gojira`, `mothra`,
`ghidorah` and `cthulhu` mods and the shared `kaiju_core` library they use. Each scenario starts a **real Luanti
client** headless under Xvfb, with the Mineclonia game (or VoxeLibre, §Running on VoxeLibre) and a fresh flat world. A scenario worldmod
builds a scene, spawns the kaiju, logs measurements as `[test] …` lines, and shuts the server down.
There are no unit tests and no mocks. The mob code runs inside the real mcl_mobs framework.

Most scenarios do not assert anything: whether a run is *good* is judged from the `[test]` lines
and the optional screenshots, against the expectations listed per scenario below. The Cthulhu
scenarios (except `cthulhu_show`) and `kaiju_truce` check themselves and end with `RESULT ok` or
`RESULT FAIL: <reasons>`. `run.sh` itself fails only on logged `ERROR[` lines, so look for the
`RESULT` line. (`compat.sh`, the upgrade check at the end of this file, asserts in its exit code.)

## Requirements

- `luanti` client 5.10 or newer on `$PATH`. The tests were developed with 5.17.0. The local server
  runs inside the client process (`--go --world …`).
- `xvfb-run` (Xvfb).
- ImageMagick `import`, only for screenshots.
- The game `$LUANTI_GAME` (default `mineclonia`) in `$LUANTI_GAME_PATH`. The default path is
  `<repo>/vendor`, i.e. `vendor/mineclonia`. `vendor/` is git-ignored and holds shallow reference checkouts:

  ```sh
  git clone --depth 1 https://codeberg.org/mineclonia/mineclonia.git vendor/mineclonia
  git clone --depth 1 https://github.com/luanti-org/luanti.git      vendor/luanti   # source reference only
  ```

  The harness only needs `vendor/mineclonia`. `vendor/luanti` is there for reading engine code;
  the binary comes from your system.

## Usage

```sh
tests/run.sh <scenario> [screenshots]
tests/run.sh kaiju_fight          # log only
tests/run.sh mothra_show 30       # plus one screenshot per second for 30 s
```

- `<scenario>` is a folder in `tests/`. Without arguments, the script prints usage and the folder
  list and exits with 2.
- `[screenshots] = N`: `import -window root` saves a 960×600 screenshot (or the size the
  scenario's `screen_w` / `screen_h` set; the Xvfb screen follows them) every second for N seconds,
  counted from **client start**. The first few frames show the loading screen, so choose N to cover
  the load time (a few seconds) plus the scenario's runtime.
  - In practice one `import` takes about 1.3 s, so N frames span more than N seconds.
  - Loading takes much longer when several runs share the machine (about 20 s with three in
    parallel), so take screenshots from a run on its own.
  - Frames taken after the shutdown are black, about 200 bytes each.
  - Match frames to scenes by file time against the `joins game` line in `client.log`.
- The whole run is capped at 180 s (`timeout 180`). A timeout does not count as a failure in itself.

What `run.sh` does:

1. Creates a per-run folder `tests/out/<scenario>-<YYYYmmdd-HHMMSS>-<pid>/` and points the symlink
   `tests/out/<scenario>` at it, so it always shows the latest run. If `tests/out/<scenario>` is a
   real directory left by an older `run.sh`, it is deleted and replaced by the link. Per-run
   folders exist because two parallel runs of the same scenario used to share one folder, and one
   deleted the other's files. Old run folders are never cleaned up. `tests/out/` is git-ignored.
2. Creates a fresh world (`gameid = $LUANTI_GAME`, default `mineclonia`; sqlite3 backends) whose `worldmods/` contains
   a symlink to the modpack folder `kaiju/` (as a user installs it, so `kaiju_core`, `gojira`,
   `mothra`, `ghidorah` and `cthulhu` are found inside the modpack), plus the scenario folder and
   `tests/lib/` as the mod `kaiju_test` (shared helpers, §Writing a new scenario). All of them
   are always loaded, whatever the scenario depends on.
3. Writes `test.conf`. The common settings come first: `enable_sound = false`, `mute_sound = true`,
   960×600, `name = tester`, `enable_damage = true`, `mg_name = flat`, `fixed_map_seed = 1`. The
   scenario's own `test.conf` is appended (creative mode, `viewing_range`, `fov`, ...; its
   `screen_w` / `screen_h` also size the Xvfb screen). On the flat
   map the surface is the top of node layer y = 8, so feet stand at y = 8.5. Scenarios spawn
   Gojira at y = 8.6.
4. Points `HOME` and `XDG_*` into the run folder, so your own Luanti settings and worlds are never
   touched. It also unsets `WAYLAND_DISPLAY` so the client uses Xvfb.
5. Starts `luanti --go` on port `30100 + PID % 800` inside `xvfb-run -a`. If the scenario
   folder contains a file `restart`, it starts the client a second time on the same world,
   logging into the same `client.log` (`kaiju_dead_reload`).
6. Extracts the `[test]` lines into `test.log` and prints them.

Run folder layout:

```
tests/out/<scenario>      -> <scenario>-<YYYYmmdd-HHMMSS>-<pid>   (symlink to the latest run)
tests/out/<scenario>-…/
  client.log   full Luanti log (client + server)
  test.log     the "[test] " lines with the prefix stripped
  s_01.png …   screenshots, if requested
  test.conf    effective settings
  client.sh    the generated launcher
  world/       the generated world (worldmods are symlinks)
  home/        isolated HOME
```

**Exit code:**

- `0`: prints `ok: <run folder>`.
- `1`: luanti wrote no (or an empty) `client.log`, or `client.log` contains a line matching
  `ERROR[` (any engine or Lua error), not counting lines that mention `poplar` (§Quirks). The
  offending lines are printed to stderr. Nothing else fails a run: a Lua traceback quoted inside a
  logged warning (such as `kaiju_core`'s dig-callback warning) does not, and neither does a run
  that was cut short (§Quirks).
- `2`: usage error or unknown scenario.

## Running on VoxeLibre

Choose the game with `LUANTI_GAME` (a game id, i.e. a folder in `LUANTI_GAME_PATH`).
VoxeLibre's id is `mineclone2`. With the games installed in `~/.minetest/games`:

```sh
LUANTI_GAME=mineclone2 LUANTI_GAME_PATH=~/.minetest/games tests/run.sh kaiju_duel
LUANTI_GAME=mineclonia LUANTI_GAME_PATH=~/.minetest/games tests/run.sh kaiju_duel  # the installed Mineclonia
LUANTI_GAME=mineclone2 LUANTI_GAME_PATH=~/.minetest/games tests/compat.sh
```

Without the two variables everything runs as before, on `vendor/mineclonia`. The game folder
is only read. Run folders are named the same for both games; `client.log` names the game.

What is game-aware (by feature, not by game id):

- `tests/lib` (`kaiju_test`): VoxeLibre 0.92.4 ignores `mobs_spawn = false` (its `vl_tuning`
  never applies a false default to the `doMobSpawning` gamerule), so the lib sets that
  gamerule when `vl_tuning` is present and `mobs_spawn` is off. Without it, chickens on the
  beach woke Cthulhu in `cthulhu_sea`.
- `gojira_arrows`, `ghidorah_fight`: `mcl_bows.shoot_arrow` takes a draw factor on
  Mineclonia (1.0) but the speed on VoxeLibre (40, its bow's maximum).
- `gojira_smash`: oak trunks and leaves are `mcl_trees:*_oak` on Mineclonia and
  `mcl_core:tree` / `mcl_core:leaves` on VoxeLibre.
- `gojira_smash`, `kaiju_settings`: griefing is read through `kaiju_core.mob_griefing`.
- `gojira_tail`: the stock `ai_step` is `kaiju_core.mcl_mobs.mob_class.ai_step`.
- `kaiju_truce`: "on a path" means a pathfinder path on Mineclonia and a straight-line
  goal (`stupid_target`) on VoxeLibre, which has no pathfinder for the kaiju.

What differs on VoxeLibre (expected, see `kaiju/README.md` §VoxeLibre):

- `gojira_arrows`: VoxeLibre's arrows raycast along their path and also hit his body, so
  `control` takes damage too. An arrow does 10 × 40 % = 4 (Mineclonia's scale with speed).
- `gojira_water`: he floats at about `immersion` 10.5 in the deep pool, tunnels out at swim
  depth (as on Mineclonia), but without a pathfinder he stays in his tunnel under the
  player's pillar instead of climbing out.
- `gojira_smash`: he walks a straight line, so less of the ring falls (`wall_stone` 1440 →
  about 1280, `trunks` 168 → about 144). The chest is dug and drops its contents.
- `cthulhu_ocean`: `idle_removed` counts VoxeLibre's own removals (mcl_core's attached-node
  check drops mushrooms in caves under the beach, within 12 nodes of his home), so it can
  fail with nothing of his doing. `ashore` can exceed 60: he grabs the player from the
  shallows and doesn't always need to step onto dry land.
- `ghidorah_heads`: side-head volleys are rarer (0-3 per run alone, Mineclonia 5-6); the
  checks after the 40 samples pass. Run it alone.

Results of 16 Nov 2026 (Luanti 5.17; `vendor/mineclonia`, the installed Mineclonia release,
VoxeLibre 0.92.4 installed). "ok" means `run.sh` exited 0 and the log reached its last line;
balance scenarios were run 3-4 times each, five in parallel, `ghidorah_heads` alone.

| Scenario | Mineclonia (vendor) | Mineclonia (installed) | VoxeLibre 0.92.4 |
|---|---|---|---|
| `gojira_anim` | ok: 6.15 n/s, breath | ok | ok: 6.0 n/s, walk 30.9 fps, breath |
| `gojira_smash` | ok: chest dug, wall 1440 → 793, trunks 168 → 29 | ok: → 745, → 20 | ok: chest dug, contents drop; wall → 1280, trunks → 144 |
| `gojira_water` | ok: swims (immersion 10), tunnels out, climbs ashore | ok | ok: swims (immersion ~10), tunnels out; ends in his tunnel under the pillar |
| `mothra_show`, `ghidorah_show`, `cthulhu_show` | ok (screens not inspected) | ok | ok (screens not inspected) |
| `kaiju_fight` | Gojira 500 → 167; Mothras 350 / 172 | → 141; 350 / 157 | → 125; 148 / 350 |
| `kaiju_duel` | Gojira wins with 104, 95, 95 HP | 95, 90, 95 | 95, 95, 95, 95 |
| `kaiju_triangle` | allies win, Ghidorah dead at 60-62 s; Gojira 291, 230, 285 | 164, 294, 294 | allies at 60-61 s; Gojira 250, 250, 201, 140 |
| `kaiju_truce` | RESULT ok | RESULT ok | RESULT ok |
| `ghidorah_heads` | 5 side volleys; all checks ok | 6; ok | 0 and 3; all checks ok |
| `gojira_arrows` | control 500 → 500, chest → 473, head → 446 | → 474, → 448 | control 500 → 496, chest → 492, head → 488 |
| `cthulhu_grab`, `cthulhu_intruder`, `cthulhu_kaiju`, `cthulhu_sea`, `cthulhu_spawns`, `cthulhu_swim`, `cthulhu_territory` | RESULT ok | RESULT ok | RESULT ok |
| `cthulhu_ocean` | RESULT ok | RESULT ok | RESULT FAIL: `idle_removed=5` only (VoxeLibre's own removals, see above) |

After the review fixes (rawget, dead bodies, flames, push, detection) the Cthulhu
scenarios, `kaiju_duel`, `kaiju_triangle`, `kaiju_truce`, `kaiju_clinch`, `ghidorah_heads`,
`gojira_smash`, `kaiju_dead_reload` and `compat.sh` were rerun on all three: everything
RESULT ok / exit 0, duel 100 (VoxeLibre), 90 (installed), 90 (vendor), triangle won by the
allies, `ghidorah_heads` side volleys 0 / 7 / 4, except: `cthulhu_ocean` on VoxeLibre (the
mushroom removals again, and `ashore=62` once), one VoxeLibre `cthulhu_grab` (the golem fell
into a pit and was never grabbed; ok in two reruns), and `kaiju_truce` on Mineclonia (2 of
6 runs: gojira3 left the active blocks during his retreat, so he was never seen arriving;
the other 4 ok).

The VoxeLibre balance rows include one run each after the last change to `vl.lua` (mobs
push each other apart): duel 100, triangle Gojira 313. The other scenarios were also run
once on VoxeLibre and exit 0: `mothra_terrain` (A: 0 samples in the wall, crossing 10.7
above it; B: the husk was down to 4 HP, not dead; C: lands before removal),
`gojira_tail` (avg 0.7 ms per smash), `gojira_punch` (speed kept; the control line shows
6.00 instead of 0.00, as the layer has no knockback), `gojira_overhead` and
`kaiju_truce_end` (RESULT ok), `kaiju_clinch` (RESULT ok), `ghidorah_fight`,
`kaiju_dig_callbacks`, `kaiju_settings` (off: nothing broken; on: wall, fire, crater).

## Scenarios

Times are seconds after the player joins. Every scenario sets noon (`set_timeofday(0.5)`) on join.

### `mothra_show`: Mothra's animations (visual)

- **Settings:** creative, `viewing_range = 160`, `fov = 80`. Depends on `mothra`.
- **Scene:** at 2 s a 3×3 cobble pillar is built from y 9 to 22, and the player is placed on top at
  (0, 23, 0), looking north (+Z) and 0.25 rad down.
- **Spawns:** at 3 s a *puppet* Mothra at (0, 17, 24), yaw 0.85π (about a three-quarter view). Its
  `on_step` is replaced so it only holds position and yaw, with no AI. The animation is set once per
  clip:

  | Time | Clip | Frames | fps |
  |---|---|---|---|
  | 3 s | fly | 50-80 | 24 |
  | 11 s | stand (hover) | 0-40 | 20 |
  | 16 s | punch / gust, **slow motion and looped** | 90-120 | 12 (the game uses 25, non-looping) |
  | 21 s | powder | 130-170 | 20 |
  | 26 s | shutdown | | |

  The die clip is not shown.
- **Logs:** nothing. `test.log` is empty. Use screenshots: `tests/run.sh mothra_show 30`.
- **Good:** the wings beat up and down symmetrically, and the hover is shallower than the fly. In
  punch the wings go **up first** (frame 100) and then sweep down hard (frame 106). In powder the
  abdomen curls **down** and the nose is up. If the punch starts with a downstroke or the abdomen
  curls up, the roll or pitch signs are inverted again (see `kaiju/mothra/README.md` §5.4).

### `mothra_terrain`: wall clearance, regaining sight, death fall

- **Settings:** creative, `viewing_range = 160`, `fov = 90`. Depends on `mothra, mobs_mc, mcl_util`.
  The player stands at (−45, 9, 0) looking east and only observes.
- **Phase A, terrain (2-24 s):**
  - Scene: a stone wall at x −20..20, z 0..2, y 9..44 (top surface y = 44.5).
  - Spawns: a Mothra at (0, 26, −25), below the wall top. At 3 s the scenario sets her goal to
    (0, 26, 25) behind the wall, with a 60 s wander timer, so she must cross the wall.
  - Logs: `A t=… pos=… node=<node at her body>` every 0.5 s, then
    `A summary: samples_inside_wall=N min_feet_above_wall_top_while_crossing=Y`.
- **Phase B, sight (24-46 s):**
  - Scene: a husk in a stone cell (interior 3×3, walls y 9..16, open top) at (0, 9, 40).
  - Spawns: a Mothra directly above the cell, so she acquires the husk and then loses sight of it
    as soon as she circles.
  - Logs: `B t=… target=… visible=… flat=<horizontal distance> y=… anim=… husk_hp=…` every 0.5 s,
    then `B summary: targeted+visible=… targeted+blind=… targeted+within6=… husk=…`.
- **Phase C, death (46-53 s):**
  - Spawns: a Mothra at (0, 60, −40). At 47 s she is killed with 1000 damage, about 50 nodes up.
  - Logs: `C killed at y=…`, then `C t=… y=…|removed` every 0.25 s.
- **Runtime:** shutdown at 53 s.
- **Good** (after the fixes; the old code in brackets):
  - A: `samples_inside_wall=0` and the crossing about 10 above the wall top. She climbs vertically
    first. [2 samples inside the stone, crossing 18 nodes below the top.]
  - B: the husk is killed (`husk_hp` ≤ 0) within about 10 s, and `visible` turns true while she is
    over the cell. [She circled blind, the target dropped to `-` after 3 s, and the husk kept
    20 HP.]
  - C: `y` reaches 8.5 (the ground) before `removed`, about 2.6 s after the kill. [Removed in
    mid-air at y 30.7.]

### `kaiju_fight`: two Mothras vs Gojira

- **Settings:** creative (the observer is never a valid target for either kaiju),
  `viewing_range = 160`, `fov = 90`. Depends on `gojira, mothra`.
- **Scene:** at 2 s a 3×3 cobble pillar is built at z = −30 (y 9-18), and the player is placed on
  top at (0, 19, −30), looking north.
- **Spawns:** at 4 s Mothra `m` at (−25, 30, 20) and `m2` at (25, 30, 20). At 8 s Gojira at
  (0, 8.6, 25), about 33 nodes from each Mothra, inside their `view_range` 64.
- **Logs:** first `egg=true` (the spawn egg is registered) and `spawned mothra=true gojira=true`.
  Then one line per second for 60 s:
  ```
  t=N  MOTHRA pos=(x,y,z) alt=<height above ground> anim=<clip> target=<name> hp=<hp>
       GOJIRA hp=<hp> target=<name> poison=<bool> anim=<clip>
       MOTHRA2 target=<name> hp=<hp>  player hp=<hp>
  ```
  `MOTHRA gone` / `GOJIRA gone` appear once an entity has been removed.
- **Runtime:** shutdown at 72 s.
- **Good:**
  - Both Mothras show `target=gojira:gojira` within a second or two of his spawn.
  - `alt` stays around 25 while circling. That is his 14.5-node height plus `CIRCLE_HEIGHT` 11, and
    never below `MIN_CLEARANCE` 10.
  - Mothra's `anim` cycles through `fly`, `punch` and `powder`. `poison=true` shows up on Gojira
    after powders.
  - Gojira targets one of the Mothras (his retaliation rule) and shows `anim=breath_up` during his
    fire breath at the flying target.
  - `player hp` stays 20.
  - Reference results: with two Mothras, Gojira went from 500 to **153** HP in 60 s, and to
    **131** in one run after the Mothra fixes. Both Mothras targeted him in all 60 samples. In a 1v1 (with
    the `m2` spawn removed locally) he went 500 → **303** and Mothra 350 → **240**. The commit
    message summarises this as "1v1 roughly even, two Mothras win". Large deviations mean the
    balance changed (see `kaiju/mothra/README.md` §6).

### `gojira_anim`: Gojira's animations and pursuit

- **Settings:** survival, `viewing_range = 140`. Depends on `gojira`.
- **Scene:** the player stands at (0, 9, 0) looking north, 0.3 rad down. A HUD label names each
  scene. The labels are German ("Szene 1: Laufen (Seitenansicht)", ...), and the same text is logged
  as `SCENE …`.
- **Spawns, puppets first** (scripted motion, no AI):

  | Time | Scene | Puppet |
  |---|---|---|
  | 2 s | walk, side view | at (−28, 8.6, 38), walking east at 4.5 n/s, clip 70-110 at `walk_speed × 4.5` fps |
  | 14 s | stand | at (4, 8.6, 24), clip 0-60 at 15 fps |
  | 19 s | fire breath | clip 150-200 at 20 fps |
  | 25 s | bite | clip 120-140 at 12 fps |
  | 30 s | die | clip 210-240 at 10 fps, non-looping |
  | 35 s | real AI | a normal Gojira at (0, 8.6, 45) hunts the player |

- **Logs:** `walk_speed=<frames per node>` first, then the `SCENE` labels. From 36 s, 12 lines
  `ai t=N moved=<n/s> vel=<n/s> anim=<clip> fps=<fps> breath=<bool>`. The player's HP is reset to
  20 every second.
- **Runtime:** shutdown at 49 s.
- **Good:** in the walk scene the feet stay planted, with no sliding: `walk_speed` is frames per
  node (`40 / WALK_CYCLE_NODES`). In the AI phase `moved` is about 6 n/s (his pursuit speed is
  measured at about 6.1 n/s), `anim=walk` with `fps ≈ walk_speed × vel`, and a breath once he is in
  range (9-32 nodes).

### `gojira_smash`: smashing, container safety, bulldozing

- **Settings:** survival, `viewing_range = 140`, `fov = 90`. Depends on
  `gojira, mcl_chests, mcl_beehives`.
- **Scene:** the player stands at (0, 9, −6) looking north. At 1 s Gojira spawns at (0, 8.6, 36).
  Only once he has locked on (`e.attack` is set) is the world built around the player:
  - a 19×19 stone ring, y 9-28 (20 high)
  - inside it, a cobble house with a wooden roof, a sand pile on the roof, and a chest at (0, 9, 3)
    holding 17 gold ingots and 5 emeralds; beside it a beehive at (−1, 9, 4) and a bee nest at
    (1, 9, 4), whose dig callbacks expect a player digger
  - outside, an oak "forest" (trunks y 9-14, leaf blocks) at z 14-26

  The player's HP is reset to 20 every globalstep.
- **Logs:** `griefing=<bool>`, then `world built, target locked`, and a report at 10, 20 … 60 s:
  `chest=<node> hive=<node> nest=<node> wall_stone=<n> trunks=<n> sand_nodes=<n>
  floating_sand=<n> items={…}` (dropped items within 25 nodes). Each change of bulldozer state is
  logged as `BULLDOZE start|end at <pos> y=<y> under=<node>`. This is done by wrapping
  `attack_melee`. Every 2 s up to 40 s a `track t=N pos=… y=… anim=…` line shows where he is.
- **Runtime:** shutdown at 62 s.
- **Good:** `griefing=true`. Once he has walked through the house (the report at 20 s, sometimes
  30 s), `chest=air` and `items` contains `mcl_chests:chest=1`, `mcl_core:gold_ingot=17` and
  `mcl_core:emerald=5`: the chest **is** dug, with a real `dig_node`, so its contents drop instead
  of vanishing. `hive` and `nest` turn to `air` as well, without an `ERROR[` line; `client.log`
  then has one `[kaiju_core] dig callback of … failed` warning per node name. `wall_stone` and
  `trunks` go down as he breaks through (1440 → about 600, 168 → about 15-40).
  `floating_sand=0` (sand falls). `under=` is never air: he never digs the layer he stands on, so
  he does not sink. `BULLDOZE start` appears after he has been stuck for 3 s, and `end` follows
  6 s later.

### `gojira_tail`: tail sweep and smash cost

- **Settings:** survival, `viewing_range = 140`, `fov = 90`. Depends on `gojira`.
- **Scene:** at 2 s the player is teleported to (0, 9, −34). 2 s later, 6-high cobble pillars are
  placed every 2 nodes in a half ring (radius 4-22, z −4..22) around the origin, and Gojira spawns at
  the origin with yaw 0 (facing the pillars, back to the player).
- **Logs:** `before: front(z7..22)=<n> sides(|x|>=6,z-4..6)=<n>`. Then 12 per-second lines
  `t=N yaw=<deg> pos=… target=… front=<n> sides=<n>`. Timing: at `register_on_mods_loaded` the
  stock `mob_class.ai_step` and Gojira's `ai_step` are wrapped, so the smash cost is measured as
  "his ai_step minus the stock ai_step inside it" with `core.get_us_time`. Ticks over 15 ms are
  logged as `SLOW tick …`, and at 19 s comes a summary `smash timing: ticks=… max=…ms avg=…ms`.
- **Runtime:** shutdown at 20 s.
- **Good:** `sides` drops when he turns round to the player, because the tail sweeps the pillars
  beside him. `front` drops as he walks. `target=player`. The average tick stays at a few ms. One
  local run gave `ticks=57 max=112ms avg=4.0ms`, with `sides` 588 → 288. Occasional single slow
  ticks happen during big turns. The sweep is capped at 6 samples per tick and deduplicated.

### `gojira_water`: wading and swimming

- **Settings:** survival, `viewing_range = 140`, `fov = 80`. Depends on `gojira`.
- **Scene:** at 2 s a cobble pillar is built, and the player is placed on it at (0, 20, −10) looking
  north and down. 2 s later Gojira spawns at (0, 8.6, 35) with `view_range` raised to 80. Once he has
  locked on, two pools are dug across his path (x −20..20):
  - **deep**, z 16-32, 22 deep (y −13..8)
  - **shallow**, z 2-12, 4 deep (y 5..8)

  The player's HP is reset to 20 every globalstep.
- **Logs:** `spawned true`, `pools built, target locked`, then every 0.5 s for 30 s:
  `t=… z=… y=… speed=<n/s> <region> immersion=… anim=… breath=… bulldoze=…`. The region is
  `DEEP(22)`, `SHALLOW(4)` or `land`.
- **Runtime:** shutdown at 38 s.
- **Good:** in the shallow pool he wades: `immersion` < 10, walking speed, feet on the bottom. In the
  deep pool he swims, because more than 10 nodes of water above his feet (`SWIM_DEPTH`) switches him
  to floating. He keeps his head above the water and moves at about 5 n/s (`water_velocity` 3.0).
  He crosses straight through instead of detouring, because `gwp_penalties.WATER = 0`.

### `gojira_punch`: punches don't stop him; target loss ends a bulldoze

- **Settings:** survival, `viewing_range = 140`. Depends on `gojira, mcl_gamemode`.
- **Scene:** at 2 s the player is placed at (0, 9, −20). 2 s later Gojira spawns at (0, 8.6, 25)
  with fire breath disabled (`_breath_cooldown = 1e9`), so he keeps walking. Once he is locked on
  and moving faster than 2 n/s:
  - three punches `g:punch(player, 1.0, {fleshy = 10})`, 0.7 s apart
  - one `e:projectile_knockback(1, dir)`, the path used by arrows and tridents
  - one control punch with `e.knock_back = true` set for that call, i.e. the stock mcl_mobs path

  At 3.5 s a bulldoze is forced (`_bulldoze_time = 6`, `go_to_stupidly(player)`), and the player
  is switched to creative, which makes him an invalid target. The player's HP is reset to 20 every
  globalstep.
- **Logs:** `locked on, walking`; for each punch, `punch N: speed before=… after=… hp a->b` (the
  speed is read right after the synchronous `punch`), and `0.25 s later speed=…`;
  `control (stock knock_back=true): speed before=… after=…`; `bulldoze forced: …`; then 3 lines
  `after target loss t=N: attack=… _bulldoze_time=… stupid_target=…`.
- **Runtime:** shutdown at 20 s.
- **Good:** `after` equals `before` for every punch and for the projectile. HP drops by 4 per punch
  (10 × 40 % armor) and is unchanged by the projectile call. The control line shows `after=0.00`,
  which proves that the stock path really zeroes his velocity. After target loss, `attack`,
  `_bulldoze_time` and `stupid_target` are all `nil`.

### `ghidorah_show`: King Ghidorah's model and animations (visual)

- **Settings:** creative, `viewing_range = 220`, `fov = 72`. Depends on `ghidorah, gojira` (for the
  meshes and textures only: the scenario registers its own puppet entities
  `ghidorah_show:puppet` and `ghidorah_show:gojira`, so none of Ghidorah's Lua runs).
- **Scene:** the player stands on a 3×3 cobble pillar at (0, 23, 0) looking north. A HUD line names
  the scene. 16 scenes of 3 s each. Every scene shows three puppets at z = 46: at x = −30 from the
  front, at x = 0 from the side, at x = 30 in three-quarter view.

  | Scenes | Shows |
  |---|---|
  | 1-10 | the clips stand, walk, fly, hover, bite (slow), beam (holds the last frame), takeoff (slow), land (slow), die, beam_fly; the flying ones 10 nodes up |
  | 11 | size comparison: Gojira, Ghidorah from behind, Ghidorah with the wings spread |
  | 12-14 | a relative rotation override of +0.6 rad on `head_c` about x, y and z |
  | 15 | `jaw_l` and `jaw_r` opened by an override (side heads beaming on their own) |
  | 16 | severed heads (scale 0): `head_r`, `head_c`, all three |

- **Logs:** only `SCENE <n> <label>`. Use screenshots: `tests/run.sh ghidorah_show 66`.
- **Runtime:** shutdown at 52 s.
- **Good:** stance feet planted in walk; wings go up **and** down in fly and hover; die ends lying
  on the ground. Scenes 12-14: x+ turns the nose down, y+ rolls, z+ turns the nose towards the
  `_l` side (the signs `aim_head` in `kaiju/ghidorah/init.lua` relies on). Scene 16 shows red neck
  stumps.

### `ghidorah_fight`: beams, head hit boxes, severing and regrowth, death

- **Settings:** survival, `viewing_range = 160`, `fov = 90`. Depends on
  `ghidorah, mothra, mcl_bows`. The player's HP is reset to 20 every globalstep.
- **Scene:** the player stands at (0, 9, −30). At 4 s Ghidorah spawns at (0, 8.6, 15) with
  `_regrow_time = 6` (30 in the game). Times below count from his spawn.

  | Time | Event |
  |---|---|
  | 13.4 s | two real arrows from the player's eye (`mcl_bows.shoot_arrow`): one at the centre head's hit box, one at the chest's |
  | 14 s | 30 damage on the `_l` head's hit box, then 500 |
  | 24-40 s | a Mothra at (20, 30, −10) |
  | 52 s | 500 damage on all three head hit boxes |

- **Logs:** `spawned true`; once a second for 54 s `t=N pos=… alt=… flying=… land=… anim=…
  target=… hp=… beam=… heads=c:<hp> l:<hp> r:<hp> dead=…` (a regrowing head shows
  `(regrow <s>,scale <x>)`); `arrows: centre head a -> b, body c -> d (anim=…)`;
  `wounded left head -> head hp …, body hp …`; `hit left head (…) -> body hp …`;
  `mothra spawned`, `mothra removed`, `hit all three heads`.
- **Runtime:** shutdown at 60 s.
- **Good:**
  - `beam=true` volleys every 8-11 s while the player is 8-40 nodes away.
  - Arrows hit: `centre head 120 -> 91, body 600 -> 570` (the body number varies by a point or
    two). A head hit takes nothing from the body and the other way round.
  - The 30-damage hit leaves the left head at 90 and the body unchanged. The 500 severs it:
    `l:…(regrow 6,scale 0.01)`, back at `l:120` six seconds later.
  - After 52 s: `dead=true`, `anim=die`, the position no longer changes.
  - Whether he takes off for Mothra depends on his target: if he keeps the player (closer than
    25 nodes), `flying` stays `nil`.

### `ghidorah_heads`: side heads beam on their own

- **Settings:** creative, `viewing_range = 160`, `fov = 72`. Depends on `gojira, mothra, ghidorah`.
- **Scene:** the player stands on a cobble pillar at (0, 17, −26). At 4 s Gojira spawns at
  (−17, 8.6, 14), Ghidorah at (17, 8.6, 14), 34 nodes apart, and Mothra at (0, 30, 30).
- **Logs:** `spawned`, then once a second for 40 s `t=N GOJIRA hp=… | MOTHRA hp=… bearing=<deg>
  elev=<deg> | GHIDORAH hp=… target=… anim=… beam=… side=… l-><target> r-><target>
  heads=c/l/r`. `bearing` and `elev` say where Mothra is as seen from his chest, relative to his
  facing; a head turns at most 60°.
- **Runtime:** shutdown at 53 s. Screenshots: `tests/run.sh ghidorah_heads 56`.
- **Good:** the fight opens with a full volley (`beam=true`, `anim=beam` or `beam_fly`). Later,
  while he bites Gojira (`anim` punch, stand or walk), there are `side=true` volleys, and Mothra's
  HP drops in those where `l->` or `r->` shows `mothra`. Runs had 4-10 `side=true` samples. A run
  on a loaded machine can have none (one did, with three clients in parallel): run it on its own.
  `heads=` rarely drops below 120: a bite of Gojira only lands on a head that is down at his
  height (lowered for the beams), not on one above him in melee.

- **After the 40 samples**, three checks of fixed bugs (each is skipped with a `skipped` line if
  he is dead by then):
  - 41 s: 500 damage on the `_l` head's hit box with `_regrow_time = 4`. Fourteen samples in the
    next 3.5 s count how often `_head_target_l` is set. Good: `severed left head: 14 samples, 0
    with a target … (another enemy in reach in N samples)` (a stump must not pick targets or
    start side volleys). If the line ends with `inconclusive: no other enemy was in reach of the
    side heads`, the 0 proves nothing: no enemy besides his main target was within 40 nodes and
    the 60° cone, so a living head would have had no target of its own either. Rerun.
  - 45.3 s: `regrown left head: hp=120 aim cache cleared=true`. Aiming is held back from 44.9 s
    (`_aim_timer = 10`), so the cache can only be empty because regrowth cleared it. Without
    that line in `regrow_step` this prints `false` (checked by reverting it).
  - 45.8 s, aiming again: `regrown left head: aim cache a/b, override a/b`. Good: both pairs
    are equal (the rotation was sent again).
  - 47 s: `_bulldoze_time = 6` is forced, which makes him take off as "stuck" within a second
    or two. Good: `stuck take-off: flying=true _bulldoze_time=nil stuck_flights=1` (the take-off
    ends the bulldoze; with it left set he took off again after landing).

### `gojira_arrows`: arrows at Gojira's chest and head

- **Settings:** creative, `viewing_range = 140`. Depends on `gojira, mcl_bows`.
- **Scene:** the player stands at (0, 9, −30). At 4 s Gojira spawns at (0, 8.6, 10). Three real
  arrows from the player's eye (`mcl_bows.shoot_arrow`, power 1, damage 10), each logged 1.5 s
  later:
  - 5 s, `control`: `kaiju_core.ensure_hitboxes` is switched off for 1.6 s, both hit boxes are
    removed and the arrow is aimed at where the chest box was;
  - 8 s, `chest`: at the chest hit box (`_hitbox_chest`);
  - 10 s, `head`: at the head hit box (`_hitbox_head`).
- **Logs:** `<label>: arrow at <pos> (<n> above his feet) -> hp a -> b`.
- **Runtime:** shutdown at 13 s.
- **Good:** `control … hp 500 -> 500` (10 nodes above his feet the server's raycast doesn't find
  him), `chest … hp 500 -> 473`, `head … hp 473 -> 447`. He paces while the arrows fly; a miss on
  `chest` or `head` with a moving `anim` is a rerun, not a bug.

### `kaiju_triangle`: Gojira and Mothra against Ghidorah

- **Settings:** creative, `viewing_range = 200`, `fov = 90`. Depends on `gojira, mothra, ghidorah`.
- **Scene:** the player stands on a cobble pillar at (0, 29, −50). At 4 s Gojira spawns at
  (−12, 8.6, 10), Ghidorah at (12, 8.6, 25) and Mothra at (−20, 30, 0).
- **Logs:** `spawned`, then once a second `t=N GOJIRA hp=… target=… anim=… dist=<to Ghidorah,
  horizontal> | MOTHRA hp=… target=… | GHIDORAH hp=… target=… flying=… alt=… anim=… heads=c/l/r`.
  When Ghidorah or Gojira is dead (or after 140 s): `END winner=allies|ghidorah|draw|none t=N
  gojira=<hp> mothra=<hp> ghidorah=<hp>`, and 8 more samples.
- **Runtime:** shutdown 8 s after the `END` line, usually at about 75 s; at 150 s at the latest.
- **Good:** Gojira and Mothra show `target=ghidorah` from the first samples (their first targeting
  rule), and he targets one of them. `END winner=allies` with Gojira alive: this is one of the two
  balance scenarios. Five runs: Ghidorah dead after 61-66 s, Gojira at 173-283 of 500, Mothra at
  248-272 of 350. `anim=beam` after the opening should be rare (0 to 2 volleys per run) and only
  after `dist` stayed above 8 for two samples. The history is in `kaiju/ghidorah/README.md` §8,
  Balance: right after the melee standoff was added, Gojira died here after 60-72 s with
  Ghidorah at 161-197 of 600. Once he is dead the two allies show `target=-` and move apart (the
  truce, see `kaiju_truce`). Before the truce existed they turned on each other here.

### `kaiju_duel`: Gojira against Ghidorah, one on one

- **Settings:** creative, `viewing_range = 160`, `fov = 90`. Depends on `gojira, ghidorah`.
- **Scene:** the player stands on a cobble pillar at (0, 23, −40). At 4 s Gojira and Ghidorah
  spawn on the line z = 15, at x = ∓gap/2, where `gap` is 20, 30 or 44 nodes, **picked at random
  per run**. On flat ground the fight is otherwise the same every time; the opening (how many
  volleys he gets in before the melee) is what differs in a real game.
- **Logs:** `spawned gap=N`, then once a second `t=N dist=… | GOJIRA hp=… anim=… | GHIDORAH hp=…
  anim=… flying=… beam=… heads=c/l/r`, and when one is dead (or after 140 s) `END
  winner=gojira|ghidorah|draw|none t=N gojira=<hp> ghidorah=<hp> gap=N`.
- **Runtime:** shutdown 2 s after the `END` line, usually at about 107 s. That is close enough to
  `run.sh`'s 180 s cap that more than five or six clients in parallel can push a run over it.
- **Good:** `END winner=gojira` with 50 to 175 HP left (10 to 35 %): he should win, narrowly. Six
  runs (gaps 20, 20, 20, 30, 30, 44): he won all six after 100-107 s with 90-104 HP. `dist` stays
  at 5.5-6.4 once they have met, `beam=true` only in the opening, and the centre head stays at
  120 (his bites hit the body). Before the retune Ghidorah won this after 105 s with 235-246 of
  600 HP left, the centre head severed twice (`kaiju/ghidorah/README.md` §8, Balance).
- Run it several times, staggered, and compare the `END` lines.

### `kaiju_truce`: Gojira and Mothra part after Ghidorah's death

- **Settings:** creative, `viewing_range = 200`, `fov = 90`, `active_block_range = 7` (112 nodes,
  so the kaiju stay active while they walk away). Depends on `gojira, mothra, ghidorah`.
- **Scene:** the player stands on a cobble pillar at (0, 29, −40). At 4 s a Ghidorah spawns at
  (0, 8.6, 20), two Gojiras at (−22, 8.6, 10) and (−22, 8.6, 30) and a Mothra at (22, 30, 20).
  They fight for 10 s, then the scenario kills Ghidorah (`health = 0`, `check_for_death`).
  **The retreat distance is shortened:** `kaiju_core.truce.distance = 40` instead of 150. At
  150 nodes the kaiju would leave the active blocks around the player and stop there; the full
  distance has not been run.
  At 8.5 s a third Gojira spawns 46 nodes from Ghidorah on the Gojiras' side, beyond fire breath
  range, so at the kill he is still following a pathfinder path towards Ghidorah.
- **Logs:** once a second `t=N gojira1 hp=… target=… pos=x,z retreat=… | gojira2 … | mothra … |
  gojira3 …` (`<name> gone` once a kaiju has wandered out of the active blocks after its
  retreat). At the kill `gojira3 at the kill: target=… on a path=… , N nodes from ghidorah` and
  `ghidorah killed: dead=… separation=… axis=… staticdata has the retreat=…` (separation: the
  first two Gojiras' centroid to Mothra, horizontally). 10 s later `gojira3 came at most N nodes
  closer to the corpse`. At 35 s after the spawn `<name>
  moved N along its direction (M sideways) until its retreat ended`, `separation a -> b`, and
  `RESULT ok` or `RESULT FAIL: <reasons>`.
- **Runtime:** shutdown at 42 s.
- **Good:** `RESULT ok`. The scenario checks:
  - the retreat started and its three fields are in the mob's staticdata;
  - no kaiju has a target in any sample taken while it retreats;
  - every kaiju moved more than 32 nodes along its direction (the Gojiras along the axis, Mothra
    against it) by the time its retreat ended;
  - the separation grew by more than 68 nodes (measured where each retreat ended; afterwards the
    normal AI wanders again);
  - `gojira3` was on a path at the kill (if not, the run says so: rerun) and never came 3 nodes
    closer to the corpse in the 10 s after it, sampled four times a second.
  Runs had `moved 36` to `39`, separation 21 → 95, and gojira3 `0.0` to `0.2` nodes closer.
  The axis depends on where the fight has taken them by then. With the fix in Gojira's `retreat`
  reverted (stale waypoints are followed first) the same run gave `gojira3 walked 12 nodes
  towards the corpse` and `gojira1 moved only -4`.

### `kaiju_truce_end`: what ends a retreat early

- **Settings:** creative, `viewing_range = 200`, `fov = 90`, `active_block_range = 7`,
  `kaiju_smash_blocks = false`. Depends on `kaiju_core, gojira, mothra, ghidorah`.
- **Scene:** the player stands on a cobble pillar at (0, 29, −40). At 4 s a stone wall is built
  at x −48..−47, z 35..65, y 9..30, the strip in front of it is cleared of trees, and `gojira1`
  spawns at (−30, 8.6, 10), `gojira2` at (−30, 8.6, 50) and a Mothra at (30, 30, 30). In the same
  step `kaiju_core.start_truce(player)` sends them on a retreat (the player stands in for the
  dead Ghidorah; full distance 150, so the Gojiras head west and Mothra east). Times below count
  from there.

  | Time | Event | Must |
  |---|---|---|
  | 2 s | Mothra is punched with `gojira2` as the puncher (a truce partner) | go on retreating |
  | 2 s | `gojira1` is punched by the player | end his retreat |
  | about 2.5 s | `gojira2` reaches the wall, which he may not break | end his retreat about 3 s later |
  | 4 s | a Ghidorah spawns 12 nodes east of Mothra | end her retreat; she targets him |

- **Logs:** `retreats started: …`, once a second `t=N gojira1 pos=x,z retreat=… | gojira2 … anim=…
  | mothra … target=…`, `after the punches: mothra hp=… retreat=… | gojira1 hp=… retreat=…`,
  `gojira2: retreat ended after N s at x=… (wall at -47)`, `2 s after ghidorah spawned: mothra
  retreat=… target=…`, and `RESULT ok` or `RESULT FAIL: <reasons>`.
- **Runtime:** shutdown at 16 s.
- **Good:** `RESULT ok`. A run had `gojira2: retreat ended after 5.50 s at x=-44`.
- The flat world has acacias. With smashing off their leaves stop a Gojira as well as a wall
  does: `gojira1` often stands in one from the start (his retreat would end after 3 s anyway),
  which is why the strip in front of `gojira2` is cleared.

### `kaiju_clinch`: Gojira and Ghidorah keep their bodies apart

- **Settings:** creative, `viewing_range = 160`, `fov = 90`. Depends on `gojira, ghidorah`.
- **Scene:** the player stands on a cobble pillar at (0, 23, −40). At 4 s Gojira spawns at
  (−15, 8.6, 15) and Ghidorah at (15, 8.6, 15), 30 nodes apart on flat ground. They fight for
  45 s. At 25 s the scenario puts Gojira right inside Ghidorah (0.7 nodes from his centre), as if
  one had landed on the other.
- **Logs:** once a second `t=N dist=… | GOJIRA hp=… anim=… turned=<deg in 0.5 s> | GHIDORAH hp=…
  anim=… flying=… turned=…` (sampled twice a second; `dist` is horizontal, centre to centre).
  `gojira placed inside ghidorah`. At the end `samples=… on the ground=… | min dist=… | closer
  than 4.5: N | mean turn per 0.5 s: …`, `apart again N s after being put inside each other`,
  and `RESULT ok` or `RESULT FAIL: <reasons>`.
- **Runtime:** shutdown at 52 s.
- **Good:** `RESULT ok`. Their collision boxes are 2.4 and 2.6 nodes half-width, so the bodies
  touch at 5.0 (the boxes are squares; 0.5 is allowed for that). The scenario checks:
  - no sample with Ghidorah on the ground is closer than 4.5, apart from the 3 s after the
    forced overlap;
  - within those 3 s they are 4.5 or more apart again;
  - there are at least 30 ground samples;
  - both lost HP between 30 s and the last sample (they are not stuck: still fighting).
  Runs had `min dist=5.5`, a steady 5.5-6.4 while they bite, and `apart again 0.5 s`. Before the
  melee standoff (`kaiju_core` §3.3) the same scene gave `dist=0.4` from t = 7 to the end.

### `gojira_overhead`: a target above his feet, inside the standoff gap

- **Settings:** survival, `viewing_range = 140`. Depends on `gojira`.
- **Scene:** the player hovers at (0, 14.3, −10), 5.8 nodes above Gojira's feet (physics override
  `gravity = 0`; put back whenever a bite has knocked him more than half a node away; HP reset
  every globalstep). At 4 s Gojira spawns at (0, 8.6, 20) with fire breath disabled.
- **Logs:** once a second for 14 s `t=N flat=<horizontal> dist=<3D> (reach 7) player N above his
  feet | anim=… target=… bites=<calls of custom_attack>`, then `RESULT ok` or `RESULT FAIL: he
  never bit the target above him`.
- **Runtime:** shutdown at 20 s.
- **Good:** `RESULT ok`, `bites` counting up from about t = 6. The standoff gap to a player is
  4.7 nodes horizontally; 5.8 nodes up that is 7.5 in 3D, beyond his reach of 7, so he has to
  close in to about 3.9. With the 3D check in `kaiju_core`'s `at_standoff` reverted he stood at
  `flat=4.4 dist=7.3` with `bites=0` for the whole run.

### `kaiju_dig_callbacks`: dig callbacks that expect a player

- **Settings:** creative, `viewing_range = 100`. Depends on `gojira, mcl_chests, mcl_beehives`.
- **Scene:** the player stands at (0, 9, −12). At 4 s a beehive at (0, 9, 4), bee nests at
  (1, 9, 4) and (0, 10, 4) and a chest with 3 diamonds at (−1, 9, 4) are placed, and Gojira spawns
  at the origin. One second later he is turned to yaw 0 and the scenario calls
  `kaiju_core.smash(self, {lookahead = 4})` directly, one pass.
- **Logs:** `gojira at <pos> node below: <node>`, then
  `after smash: <the four nodes> | items: <dropped items>`.
- **Runtime:** shutdown right after the pass, about 5 s.
- **Good:** `after smash: air air air air | items: mcl_chests:chest, mcl_core:diamond 3`, and the
  run is `ok` (no `ERROR[`). In creative mode `mcl_beehives`' `after_dig_node` indexes the digger's
  inventory and fails without a digger; `client.log` has the two
  `[kaiju_core] dig callback of … failed` warnings instead of a server crash. If all four nodes
  are still there, he was not facing them.

### `kaiju_settings`: the three modpack settings

- **Settings:** survival, `viewing_range = 140`, `fov = 90`, and `kaiju_smash_blocks`,
  `kaiju_gojira_fire`, `kaiju_ghidorah_beam_blasts` all `false`. Depends on
  `gojira, ghidorah, mcl_fire`.
- **Scene:** the player stands at (0, 9, −12) with `pointable = false`, so that beams aimed at him
  pass through and hit the ground behind him. Two phases of 10 s, `off` with the settings from
  `test.conf` and `on` after `core.settings:set_bool(…, true)` at runtime, which is the default.
  Each phase:
  - a cobble wall (x −5..5, y 9..15, z 14..15) and a Gojira behind it at (0, 8.6, 21), with his
    own breath disabled; he has to break the wall to reach the player;
  - 1 s later a `gojira:flame` shot at a wall of planks at x = 30;
  - at 5 s Gojira is removed and a Ghidorah spawns at (0, 8.6, 8), who fires a volley at the
    player; at 10 s he is removed.
- **Logs:** `griefing=true` (the gamerule), then one line per phase:
  `off|on: smash=… fire=… blasts=… -> wall_broken=<cobble nodes gone> fire=<fire nodes at the
  planks> beams_fired=<bool> crater=<new air nodes in the ground, y 6..8>`.
- **Runtime:** shutdown after the second phase, about 25 s.
- **Good:**
  ```
  off: smash=false fire=false blasts=false -> wall_broken=0 fire=0 beams_fired=true crater=0
  on: smash=true fire=true blasts=true -> wall_broken=124 fire=1 beams_fired=true crater=4
  ```
  `off` must be all zeros with `beams_fired=true` (the beams did fire, they just broke nothing).
  `on` must be above zero in all three; the exact numbers vary.

### `cthulhu_show`: Cthulhu's model and animations (visual)

- **Settings:** creative, `viewing_range = 200`, `fov = 72`. Depends on `cthulhu, gojira, ghidorah`.
- **Scene:** 16 scenes of 3 s with own puppet entities (no AI): every clip from the front, the
  side and three-quarter view, a size comparison with Gojira and Ghidorah, the head and feeler
  overrides, and a marker on the grip point. A HUD line names the scene.
- **Logs:** `SCENE <n> <label>`. Use screenshots: `tests/run.sh cthulhu_show 40`.
- **Good:** see the header of `tests/cthulhu_show/init.lua` and
  [`kaiju/cthulhu/README.md`](../kaiju/cthulhu/README.md) §5.

### The Cthulhu scenarios: sea, ocean, results

`cthulhu_territory`, `cthulhu_sea`, `cthulhu_grab`, `cthulhu_kaiju`, `cthulhu_swim` and
`cthulhu_intruder` share one scene, built by `kaiju_test.sea` (`tests/lib/init.lua`): water from
(−22, −13, 14) to (22, 8, 58) on a stone floor (45 × 45 nodes, 22 deep, surface at y = 8.5), with
30 nodes of air cleared above it. Cthulhu is spawned at its centre, (0, −13.4, 36), which becomes
his home. The shores are vertical walls, so where he comes out he lifts over the edge or digs a
ramp into it; water then runs into the ramp, and the next time he may stay in it.

`cthulhu_ocean` and `cthulhu_spawns` run on generated terrain instead: their `test.conf` sets
`mg_name = v7` and `fixed_map_seed = 7`, and `kaiju_test.ocean` generates 130 nodes around a
sandy beach at (−1095, 441), `kaiju_test.OCEAN_SHORE`. The sea is to its south-west, 13 deep 35
nodes out. Generating takes about 10 s. Plants, structures and mobs differ from run to run.

All set `active_block_range = 7`, and all but `cthulhu_spawns` set `mobs_spawn = false`
(naturally spawned animals would be intruders). The survival scenarios top up the player's HP
every step.

Each ends with `VALUES key=value …` and then `RESULT ok` or `RESULT FAIL: key=value (want …); …`
(`kaiju_test.result`). The **Good** lists below give the checked ranges; a value of `nil` means
that phase never finished. Values without a range are informative.

### `cthulhu_territory`: neutral, intruder, giving up, leash

- **Settings:** survival. Depends on `cthulhu`. The grab is switched off (`_grab_cooldown = 1e9`),
  because the scenario moves the player around.
- **Phases:**

  | Phase | Player | Expected |
  |---|---|---|
  | A, 6 s | (0, 9.5, −16): 52 nodes from home | no target, `anim=dormant`, on the sea floor |
  | B | (0, 9.5, 4): on the beach, 32 from home | target within a second; `rise`, then `roar`; he swims over and comes ashore; after 20 s on land `returning=true` |
  | C | back at 52 nodes | he goes home and rests; no target |
  | D, 8 s | on the beach again | target again |
  | E | (0, 9.5, −40): 76 from home, beyond the leash | target dropped; he goes home |

- **Logs:** `spawned home=… saved_home=… home_depth=…` (`saved_home` is read back from the
  mob's staticdata), one line per second with position, `home_dist`, `sea`, `depth`
  (`_immersion_depth`), `target`, `anim`, `land_time`, `returning`, `valid_enemy`, the probed
  `floor` and `surface`, `hp`.
- **Good:** `saved_home` (equals (0, −13.5, 36)), `neutral_outside`, `asleep`, `rise`, `roar`
  true; `ashore` true (he had a target with less than 1 node of water around him, south of the
  sea's edge); `woke` 0-2 (measured 0.5); `gave_up_land_time` 19-20.6; `home_again` 1-30
  (measured 7-8); `leash_drop` 0-1.5 (0.5); `home_after_leash` 1-30 (5).

### `cthulhu_sea`: diving and rising, regeneration, land weakness, flight

- **Settings:** survival. Depends on `cthulhu, mcl_util`. Grab switched off.
- **Note:** the water's edge is in reach of his smashing, so the player drops into the pit
  Cthulhu digs there and stands 8 nodes below the surface, in the air. Cthulhu must keep his
  head out all the same (a target only counts as under water if it is in water).
- **Phases:** asleep (5 s); player at the water's edge (0, 9.5, 12) for 12 s; 100 damage from the
  player in the water, then 15 s of regeneration; player inland at (0, 9.5, −2), and 100 damage
  as soon as he stands on dry land; his HP are set to 20 %; when he is back on the sea floor his
  HP are set to 69 % (125 s of regeneration skipped) and the player returns to the water's edge;
  when he has come back for the player his HP are set to 20 % again and, a second later,
  `_flee_time` to 179 s (the flee timeout is 180 s).
- **Logs:** one line per second (`head_out` = his top above the surface, `hp`, `fleeing`,
  `valid_enemy`, the player's position and node, …).
- **Good:** `asleep_y` −13.7..−13.3, `asleep_targetable=false`; `head_out` 3.5-5.5 (4.0; 5.0 when he ends up on the ledge of the shore he broke),
  `risen_targetable=true`, `risen_sea=true`; `hit_water` 100, `hit_land` 150; `regen_4s` 0 and
  `regen_15s` 17-23 (none for 5 s, then 2 HP/s); `fleeing=true flee_target=false`; `dived`
  (seconds until he is no valid enemy) 1-15 (measured 5.5); `flee_home` set; `flee_regen`
  1.5-2.2; `back` set, `back_hp` 385-400 (70 %), `back_target` set; `fled_again=true`,
  `timeout_back` 0-2.5 (seconds after `_flee_time` was set until the flight is over; 1.0),
  `timeout_hp` 100-140 (still about 20 %), `timeout_target=true`, `cornered=true` (8 s later he
  is not fleeing again). `sea_walk=0`: in sea mode with a target he never shows "walk" (on
  VoxeLibre it did while the layer dropped his own `gopath` and `set_animation`).

### `cthulhu_grab`: the tentacle grab and the aura

- **Settings:** survival. Depends on `cthulhu, mcl_util, mcl_boats, mobs_mc`.
- **Phases:**

  | Phase | Victim | Expected |
  |---|---|---|
  | `boat` | the player, driving a boat at (0, 9, 22) | pulled out of the boat, held under water, released after about 6 s; the boat is still there, without a driver |
  | `golem` | an iron golem on the east shore (the player waits beyond the leash) | the same |
  | `victim_death` | a second golem on the south shore | 1 s into the hold the golem is killed: released at once, the grab is over |
  | `struggle` | the player on the west shore | 1 s into the hold Cthulhu takes 30 damage: released at once |
  | `death` | the player on the north shore | 1 s into the hold Cthulhu is killed: released at once |

- **Logs:** `in boat: true`, a line every second (`grab_t`, the victim's position and node,
  `attached`, `grips` = number of `cthulhu:grip` entities, `nausea`, `darkness`, `squeezed` = HP
  the player lost while attached). A `timeout in phase …` line means a grab never happened.
- **Good:** `boat_pulled=true boat_stays=true boat_driver=nil`; `boat_hold` and `golem_hold`
  5-6.5; `boat_min_y` and `golem_min_y` at most 6.6 (2 nodes under the surface; measured about
  5); `boat_released_in=mcl_core:water_source`; `boat_squeezed` 8-12; `victim_death_release`,
  `struggle_release` and `death_release` 0-0.5 (0.2); `victim_death_grab_over=true`;
  `dead=true`; `nausea=true darkness=true`; `buried` 0-4: the longest run of 0.25 s samples in
  which a held victim's feet or head were inside a solid node (the grip passes through the shore
  edge on its way; staying there was the bug; measured 2); `grips_left` 0, one second after the
  end. `boat_grips` and `death_grips` are counted in the step of the release and may still be 1.

### `cthulhu_kaiju`: Cthulhu and the other kaiju

- **Settings:** creative (the player watches from a pillar at (−36, 23, 10), at a corner of the sea). Depends on
  `cthulhu, gojira, ghidorah, mothra, mobs_mc`.
- **Part 1, on land** at (0, 8.6, −70), trees cleared. This Cthulhu's `get_active_target` is
  replaced on the entity, so he picks no target himself and only the others' rules are measured:
  - Gojira, then Ghidorah: 4 s at 50 nodes, then moved to 28 nodes.
  - Mothra: 6 s with a calm Cthulhu. `mothra_spares`: a husk 4 nodes from his centre, put back
    there and healed every half second, until she has gusted and powdered it (at most 25 s).
    Then he is given an iron golem as his target, until she has hurt him; then he is calm again.
- **Part 2, at sea:** a fresh Cthulhu at home, and a Gojira at (−30, 8.6, 2) on a truce retreat
  along the beach (inside the territory). After 6 s the retreat is cleared. They fight for 30 s
  (or until Cthulhu is below 200 HP or Gojira below 100). `truce_again`: Gojira is put on a
  retreat again for 5 s (goal 45 nodes along the beach). `regain`: until both attack each other
  and Cthulhu's head is out of the water; then Cthulhu's HP are set to 100 (`dive`).
- **Logs:** a line every second for both.
- **Good:** `gojira_far=true` and `ghidorah_far=true` (no attack at 50 nodes; `…_far_min`
  40-60) with `…_near` 0-2 (seconds until they target him at 28; 0.5); `mothra_calm=true`;
  `spares_gust=true`, `spares_powder=true`, `spares_husk_damage` at least 13 and
  `spares_cthulhu_hp` 550; `mothra_aggressive` 0-2 and `mothra_hurts_aggressive=true` (the
  control: as her target he is hurt); `mothra_lets_go` 0-2; `truce_ignored=true` with
  `truce_max_home_dist` below 48; `intruder` 0-2; `gojira_fights_back` 0-20 (2-2.5); both HP
  after the fight below their maximum (measured: Cthulhu 369-376, Gojira 385-410 after 30 s);
  `truce_lets_go` 0-1 and `truce_kept=true` (no target from 1.5 s on, Gojira still retreating);
  `regain` 0-20. The dive must show that Gojira loses him because he is under water, not
  because of the 32 nodes of Gojira's rule or 3 s out of sight: `attacked_until_submerged=true`,
  `submerged_dist` at most 31, `lets_go_delay` 0-1 (measured 0.0: the same half second).

### `cthulhu_swim`: a swimming Gojira

- **Settings:** creative, the player on the same pillar. Depends on `cthulhu, gojira`.
- **Scene:** Cthulhu at home, a Gojira spawned in the water at (12, 0, 36): he swims, his feet
  10 nodes under the surface and his head out of it. Before the fix Cthulhu stayed fully
  submerged beside him and killed him without ever being targeted.
- **Phases:** `fight` 30 s; then Cthulhu's HP are set to 100 (`dive`); `lost` 6 s after Gojira
  let go.
- **Good:** `cthulhu_attacks` 0-2; `gojira_fights_back` 0-12 (measured 0.5); `gojira_depth` at
  least 8 (his feet that far under the surface: he does swim); `head_out_share` at least 0.9 (share of the samples, from 8 s after he
  attacked, with his top more than 2 nodes above the surface; 1.0); `targetable_share` 1;
  both HP below their maximum (Cthulhu 426, Gojira 404); `attacked_until_submerged=true`,
  `submerged_dist` at most 31, `lets_go_delay` 0-1; `lost=true` (Gojira takes no target while
  he is under water) with `lost_max_dist` at most 31.

### `cthulhu_intruder`: who wakes him, and giving up out of reach

- **Settings:** survival. Depends on `cthulhu, mobs_mc`. The player waits at (0, 9.5, −16),
  outside the territory, until the last phase.
- **Scene:** a sealed 3 × 3 × 3 cell in a 7 × 7 × 7 block of stone around (−31, −5, 36), under
  ground and 9 nodes west of the sea; a one-node cobble pillar in the sea at (0, 20) up to
  y = 40.
- **Phases:**

  | Phase | What | Expected |
  |---|---|---|
  | `flyers`, 10 s | a bat 2 nodes above the sea and an iron golem 8 nodes above it, both held in place (`on_step` replaced) | asleep |
  | `golem_swims` | the golem is put into the water | target within 4 s (control) |
  | `cave`, 10 s | a zombie in the cell | asleep, no node removed within 12 nodes of him |
  | `shaft` | a shaft from the cell up to the sky | target within 3 s (control) |
  | `tower` | the player on top of the pillar, 30 nodes above his head | target; he swims there, breaks the pillar's foot (the rest hangs in the air) and gives up after 12 s out of reach |
  | `ignored` | the player stays | home and asleep for 12 s more |

  Between the phases the scenario waits until he sleeps at home again (`settle`).
- **Logs:** a line every second with `land_time`, `stall` (`_stall_time`), `returning`,
  `ignored` (`_ignored`), `removed`.
- **Good:** `flyers_ignored=true`, `bat_alive=true`; `golem_in_water_woke` 0-4 (0.5);
  `settled_before_cave=true`; `cave_ignored=true`, `cave_removed` 0, `zombie_alive=true`;
  `shaft_woke` 0-3 (0.5); `settled_before_tower=true`; `tower_woke` 0-2; `tower_land_time` at
  most 0.5 (he never stood on dry land); `gave_up` 12-24 s after waking (15.0); `gave_up_dist`
  at most 12 nodes from the pillar (3.1); `home_again` 1-30 (4.5); `stays_asleep=true`.

### `cthulhu_ocean`: real terrain

- **Settings:** survival, `mg_name = v7`, `fixed_map_seed = 7`. Depends on `cthulhu`. Grab on.
- **Scene:** he is spawned on the beach at `OCEAN_SHORE`, as with the egg, and then moved to the
  home he chose (the walk is skipped). The player's two spots are on the line from that home
  through the spawn spot: `beach`, 46 nodes from home (in the territory), and `far`, 90 nodes
  (beyond the leash).
- **Phases:** `settle` (until he sleeps); `asleep` 10 s with the player at `far`; `beach`: the
  player at `beach` until Cthulhu has stood on dry land and finished a grab (at most 70 s);
  `leave`: the player at `far`, until he sleeps at home again.
- **Logs:** `spawned at … home=… home_depth=… beach=… far=…`, a line every second (`floor`,
  `surface`, `removed`, the player's position, `attached` and the node at his head).
- **Good:** `home_dist` 8-48 and `home_depth` at least 15 (measured 44 and 16: the nearest
  ring with deep water, not the deepest column at 48); `settled=true`, `asleep=true` (the idol
  pose on the sloping floor); `idle_removed` 0; `woke` 0-2, `rise=true`; `ashore` 1-60 (seconds
  until he has a target and less than 1 node of water around him; 35); `grabs` at least 1,
  `buried` 0-4 samples of 0.25 s (0); `let_go` 0-2, `home_again` 1-60 (8.5).
  `rest_above_floor` is informative.

### `cthulhu_spawns`: natural spawning around his home

- **Settings:** as `cthulhu_ocean`, but `mobs_spawn = true`. The player stands 60 nodes from
  his home (outside the territory), so mobs spawn around both.
- **Runtime:** 80 s after he is at home.
- **Logs:** `TARGET <name> at <pos>, <n> from home, sky light <n>: ok|BAD` for every target he
  takes, a status line every 5 s, and at the end the names of the mobs that were within 48
  nodes of his home, and of those that were there while he had no target.
- **Good:** `bad_targets` 0 (every target was a player or a mob that is no water creature and
  had natural light of at least 8 above it), `max_home_dist` at most 80. `targets` and `engaged`
  (seconds with a target) are informative and differ from run to run: animals on the beach do
  wake him. One run: axolotl, bat, cod, creeper, dolphin, skeleton and squid in the territory,
  no target.

### `readme_shots`: screenshots for the published README

- **Settings:** creative, mapgen v7 seed 7, 1280×720, `viewing_range = 240`,
  `chat_log_level = none`. Depends on all four kaiju and `kaiju_test`.
- **Scene:** a plains beach at (−1664, 80) that slopes into the ocean to the west. Puppet
  entities with the kaiju's meshes, sizes and glow (no AI, frozen poses) and a floating camera
  (the player, gravity 0). All HUD elements and the chat are removed, so neither the hearts
  nor the client's own `poplar` error show. The first scene is set up once unlogged, so the
  client has the map blocks (and their light) when it is shot; then five scenes of 6 s:
  1 all four (hero), 2 Gojira breathing fire, 3 Mothra in flight, 4 Ghidorah firing beams,
  5 Cthulhu in the sea, roaring. The breath and the beams are particles drawn by the scenario.
- **Logs:** the ground heights along the beach, then `SCENE <n> <label>`.
- **Use:** `tests/run.sh readme_shots 40`; `tools/publish.sh` runs it and takes the last
  frame of each scene (by file time against the `SCENE` lines) as
  `screenshots/<n>-<name>.png` of the published repository.
- **Good:** each kaiju whole, lit (not black: a puppet in a map block the client doesn't have
  yet is drawn black) and clearly in frame; no text on screen.

### `kaiju_dead_reload`: a kaiju killed just before shutdown

- **Settings:** creative, `mobs_spawn = false`. Depends on all four kaiju and `kaiju_test`.
  Has a `restart` file: `run.sh` starts it twice on the same world.
- **Start 1:** spawns Gojira, Mothra, Ghidorah and Cthulhu near the player, kills them
  (`health = 0`, `check_for_death`) 3 s later and shuts down 1 s after that, during their
  die clips. Logs `start 1: killed 4 of 4`.
- **Start 2:** 4 s after join counts the kaiju entities and ends with `VALUES left=… which=…`
  and `RESULT`.
- **Good:** `left=0`. On VoxeLibre the body is removed by a `core.after` that a shutdown
  loses; before the fix the four came back as dead bodies that could not be killed
  (`left=4`).

## Upgrade check: `compat.sh`

```sh
tests/compat.sh                 # old layout = the current mods, linked as four folders
tests/compat.sh /path/to/old    # old layout = a folder holding kaiju_core/ gojira/ mothra/ ghidorah/,
                                # e.g. from: git archive <old commit> kaiju_core gojira mothra ghidorah | tar -x -C /path/to/old
```

Checks that a world made with the four separate mod folders keeps its kaiju and eggs when the
folders are replaced by the `kaiju` modpack. Unlike `run.sh` it installs the mods the way a user
does, in `~/.minetest/mods` of an isolated `HOME`, and enables them in `world.mt` with the paths
that the Select Mods dialog writes (`load_mod_gojira = mods/gojira`). The world scenario is
`tests/kaiju_compat` (creative mode; not meant for `run.sh`). One world, three starts:

| Step | Install | `world.mt` | Expected line |
|---|---|---|---|
| 1 | `mods/kaiju_core`, `mods/gojira`, `mods/mothra`, `mods/ghidorah` | `mods/<mod>` | `spawned: gojira:gojira=1(hp …, steps …, at …) mothra:mothra=1(…) ghidorah:ghidorah=1(…) \| eggs: …=true …=true …=true`: the three kaiju are spawned, their eggs put in the inventory, the world saved |
| 2 | `mods/kaiju/` | `mods/kaiju/<mod>` | `loaded: …` with `steps` above 0 for all three (their `on_step` runs again) and all three eggs `true` (still in the inventory, still registered items) |
| 3 | `mods/kaiju/` | `mods/<mod>` again, the stale paths | `kaiju mods NOT loaded`, plus Luanti's `ERROR[ServerStart]: The following mods could not be found` and `LuaEntity name "…" not defined` |

Step 3 is for information: it shows what happens when a user forgets to re-enable the modpack in
a world. Luanti starts the world without the mods; the kaiju there are unknown entities, which
drift off (flyers keep their velocity) or sink into the ground. In a run where this step came
before the correct one, only Gojira was left afterwards, 4 nodes down in the ground. Hence the
order in `kaiju/README.md`: fix `world.mt` **before** starting the world.

Output goes to `tests/out/compat-<time>-<pid>/` (`step1.log` … `step3.log`, `test.log`). Exit code
0 and `ok: <folder>` if step 2 found all three kaiju stepping and all three eggs, otherwise 1.
The kaiju fight each other while the world runs, so HP and positions differ between the steps,
and a `=0` count with `steps` above 0 means a flyer has left the active area again.

## Writing a new scenario

1. Create `tests/<name>/` containing:
   - `mod.conf`:
     ```
     name = <name>
     depends = gojira, mothra   # whatever the scenario uses
     ```
     A scenario that calls `kaiju_core` directly should list it too. It is linked into every
     test world anyway. So is `kaiju_test` (`tests/lib/init.lua`); list it to use its helpers:
     `log`, `flat` (horizontal distance), `name_of`, `keep_players_alive`, `sea`, `ocean`,
     `column`, `on_ground`, `count_removed` and `result` (the `VALUES` and `RESULT` lines from a
     table of values and a list of expected ranges).
     The folder name and the mod `name` should match. `run.sh` links the folder into
     `worldmods/<name>`.
   - `test.conf`: the scenario's settings, appended after the common ones (`creative_mode`,
     `viewing_range`, `fov`, ...). It may be empty, but it must exist (`run.sh` `cat`s it).
   - `init.lua`: builds the scene, spawns the kaiju, logs, and shuts down:
     ```lua
     local function L(s) core.log("action", "[test] " .. s) end
     core.register_on_joinplayer(function(player)
     	core.set_timeofday(0.5)
     	core.after(2, function()                 -- let the map load first
     		player:set_pos({x = 0, y = 9, z = -20})
     		core.after(2, function()             -- again after a teleport
     			local g = core.add_entity({x = 0, y = 8.6, z = 20}, "gojira:gojira")
     			for t = 1, 10 do
     				core.after(t, function()
     					local e = g:get_luaentity()
     					if e then L(("t=%d hp=%d"):format(t, e.health)) end
     				end)
     			end
     		end)
     	end)
     	core.after(20, function() core.request_shutdown("done") end)
     end)
     ```
2. Always call `core.request_shutdown`. Otherwise the run only ends at the 180 s timeout.
3. Put everything you want to read in `[test]` lines. Use one line per sample, with `key=value`
   pairs, so runs can be compared with `diff` or `grep`.
4. Write down in this file what a good run looks like.

## Quirks and pitfalls

- **Targets need line of sight.** mcl_mobs' nearest-target rules only acquire what
  `target_visible` (eye to eye) can see, within `view_range`. Gojira's `view_range` is **58**,
  Mothra's and Ghidorah's are 64. Place the player or bait in the open, within range, and raise it on a pillar if
  terrain could block the view. `gojira_water` raises his `view_range` to 80 for that reason.
  Several scenarios also build obstacles only *after* `e.attack` is set, so the target is locked
  before the view is blocked.
- **Spawn after the map has loaded.** Wait about 2 s after join *and* after every teleport
  (`core.after(2, …)`) before calling `add_entity`, `bulk_set_node` or raycasts. Around a freshly
  placed player the mapblocks are not generated or loaded yet. Nodes set there get overwritten by
  mapgen, raycasts (such as Mothra's `ground_y`) find no ground, and entities can land in unloaded
  blocks.
- **Puppets: call `set_animation` once, not every step.** A puppet is the real entity with its
  `on_step` replaced (no AI), driven by `object:set_animation(range, fps, 0, loop)`. The raw object
  call re-sends the animation each time it is called, and the client restarts the loop, so a puppet
  that sets its animation every step looks frozen on the first frame. Set it once when the scene
  changes. Mob code may call `mcl_mobs`' `self:set_animation(name)` every step, because that function
  returns early when the name is unchanged.
- **Timing: use `core.get_us_time`, not `os.clock`.** In this setup the server runs in the same
  process as the rendering client. `os.clock` measures CPU time of the whole process, including
  rendering, so it inflates server-side measurements. `core.get_us_time()` is wall-clock time in
  microseconds (see `gojira_tail`).
- **Parallel runs: start them a few seconds apart.** Two `xvfb-run -a` started in the same instant
  can pick the same display. Both clients then share one Xvfb, and the run that finishes first
  takes it down and the other client with it. `run.sh` still prints `ok`, because a client that
  was killed logs no `ERROR[`. The same goes for an engine crash (Luanti 5.17 segfaulted in one
  of about 40 runs) and for the 180 s timeout. So check that `test.log` reaches the scenario's
  last line: `gojira_smash` must have a `t=60` report, `gojira_anim` 12 `ai t=` lines.
- **Ports.** Each run listens on `30100 + PID % 800`, so parallel runs, including of the same
  scenario thanks to the per-run folders, don't collide. `run.sh` handles this. Don't hard-code a
  port. Two runs whose PIDs differ by a multiple of 800 still get the same port; the second
  fails with `ERROR[Main]: ServerError: AsyncErr: Failed to bind socket`. Rerun it.
- **The "poplar" error is ignored.** Mineclonia itself references a missing texture
  (`mcl_poplar_poplar_shelf.png`, `ERROR[Main]: generateImagePart(): Could not load image …`). The
  error grep skips lines containing `poplar`. Any other `ERROR[` line fails the run.
- **A run that never started still passes.** If `luanti` fails before it writes `client.log`, both
  greps fail silently (`|| true`, and the `if` swallows the exit status). The script then prints an
  empty log and `ok`. An empty `test.log` for a scenario that should log means: check `client.log`
  and the run folder.
- **Creative vs survival.** In creative mode (and on peaceful) players are never valid mob targets.
  `kaiju_fight`, `kaiju_triangle`, `kaiju_duel`, `ghidorah_heads` and `mothra_show` use creative so the observer
  stays out of the fight. The Gojira scenarios, `ghidorah_fight` and `kaiju_settings` use survival
  so the kaiju hunt the player, and they top up the player's HP every step or
  second.
- **Big fills: use a VoxelManip.** Setting 45,000 water nodes with `bulk_set_node` overflows
  mcl_redstone's event queue (`ERROR[Server]: [mcl_redstone]: Maximum number of queued redstone
  events`), which fails the run. The Cthulhu scenarios' `sea` function writes a VoxelManip, after
  `core.emerge_area` has loaded the area.
- **The flat mapgen has caves.** A basin dug into the ground can have air pockets under its
  floor, and VoxelManip water does not flow into them. `sea` therefore lays a stone floor.
- **Natural spawns.** Animals spawn in the flat world. For a mob that reacts to any land mob
  (Cthulhu), set `mobs_spawn = false` in `test.conf`.
- **An attached player can't be moved.** `set_pos` does nothing while the player hangs on
  Cthulhu's grip (or sits in a boat). `cthulhu_territory` and `cthulhu_sea` switch the grab off.
- **A big `health` set right after `add_entity` did not last** (a husk given 1000 was at 19 a
  few seconds later). To keep a small mob alive under fire, heal it every tick and add up what
  it lost (`cthulhu_kaiju`, `mothra_spares`).
- **Flat world, with two exceptions.** All scenarios use `mg_name = flat`, except `cthulhu_ocean`
  and `cthulhu_spawns` (mapgen v7; a scenario's `test.conf` comes after the common settings and
  overrides them). Nothing else covers hills, caves or water other than the pools that
  `gojira_water` builds and the sea of the Cthulhu scenarios.
- **Something always removes nodes.** In a generated world the game itself calls
  `core.remove_node` about 18 times a second (plants, leaves). `kaiju_test.count_removed` only
  counts removals within 12 nodes of a position.
- **Water runs into what he digs.** A ramp dug into the test sea's wall fills with flowing
  water; how fast depends on the run. A scenario must not expect him to be out of the water at
  a spot he has dug up before.
