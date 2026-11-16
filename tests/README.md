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
- `KAIJU_TEST_CONF` (environment): lines appended to the run's settings after the scenario's
  `test.conf`, so they win. `KAIJU_TEST_CONF='kaiju_duel_gap = 30' tests/run.sh kaiju_duel`
  fixes the duel's starting gap; `KAIJU_TEST_CONF='enable_damage = false' tests/run.sh
  kaiju_knockback` is that scenario's second run.

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
- `kaiju_truce`: "on a path" means `waypoints` (both games; on VoxeLibre from the layer's
  own pathfinder) or, on VoxeLibre, a straight-line goal (`stupid_target`).
- The nav_* courses, `gojira_smash` and `kaiju_triangle` log a `NAV` line on VoxeLibre
  (`kaiju_core._vl_nav_stats`: the layer's path searches and their time). On Mineclonia
  there is no such line and `nav_max_us` is 0.

What differs on VoxeLibre (expected, see `kaiju/README.md` §VoxeLibre):

- `gojira_arrows`: VoxeLibre's arrows raycast along their path and also hit his body, so
  `control` takes damage too. An arrow does 10 × 40 % = 4 (Mineclonia's scale with speed).
- `gojira_water`: he floats at about `immersion` 10.5 in the deep pool, tunnels out at swim
  depth and climbs up to the player's pillar, as on Mineclonia. (Until 16 Nov 2026 he stayed
  in a tunnel under the pillar. That was a terrain problem, not the missing pathfinder:
  VoxeLibre's stone has no terrain group, so smashing cut the steps he climbs on. `vl.lua`
  now names the stone nodes as terrain.)
- `gojira_smash`: the forest is in his way, so the pathfinder gives him a short path and
  then none: he stands in front of it for 3 s, then bulldozes one straight line through
  forest, ring and house to the player (there at about 13 s). He never turns, so less of
  the ring falls than on Mineclonia, where he swerves and his tail sweeps (`wall_stone`
  1440 → about 1285, `trunks` 168 → about 144; Mineclonia about 600-760 and 15-90). The
  chest is dug and drops its contents. How much falls depends on the route on both games
  and is not a target; the RESULT checks lower bounds only.
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
| `gojira_water` | ok: swims (immersion 10), tunnels out, climbs ashore | ok | ok: swims (immersion ~10), tunnels out, climbs to the pillar (RESULT ok, y 7.5) |
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

### Results after the VoxeLibre pathfinder (16 Nov 2026)

`vl.lua` got terrain names for stone, and then a pathfinder (`kaiju_core/vl_path.lua`).
Mineclonia's code paths did not change. Luanti 5.17, `vendor/mineclonia` and VoxeLibre
0.92.4, four scenarios in parallel, `ghidorah_heads` alone; the nav_* courses also on the
installed Mineclonia release.

| Scenario | Mineclonia (vendor) | VoxeLibre 0.92.4 |
|---|---|---|
| `nav_wall` | RESULT ok: reached 5.5 s (6.0 and 15.0 under load; installed 6.2) | RESULT ok: 4.0-5.5 s |
| `nav_wall_wide` | RESULT ok: 8.2 s (22.5 and 38.5 under load, after bulldozes; installed 10.8) | RESULT ok: 6.5-7.5 s |
| `nav_cliff` | RESULT ok: top 3.0-4.0, reached 4.5-5.0 (installed 3.0, 4.0) | RESULT ok: top 2.8-3.0, reached 3.8-4.0 |
| `nav_forest` | RESULT ok: 7.8, 9.2 s (installed 10.2) | RESULT ok: 8.0-8.2 s |
| `nav_water` | RESULT ok: ashore 8.0-8.5, reached 10.2-10.8 (installed 7.2, 8.8) | RESULT ok: ashore 3.5-3.8, reached 5.5 |
| `nav_protected` | RESULT ok: 5.2, 7.2, 16.2 s (installed 5.2) | RESULT ok: 4.0-4.2 s |
| `nav_far` | RESULT ok: 5.4-6.0 n/s in 6 runs (installed: 3 ok; one 4.3 n/s, the player had been moved 14 nodes during the run) | RESULT ok: 5.9-6.0 n/s |
| `nav_pace` | RESULT ok: moved 58-59, max_y 8.5 (installed 60) | RESULT ok: moved 111-113, max_y 8.5 |
| `gojira_water` | 3 of 6 ok (see the scenario) | RESULT ok, 4 of 4 |
| `gojira_smash` | RESULT ok: wall −681 and −732, trunks −79 and −134 | RESULT ok: wall −155, trunks −24 |
| `kaiju_settings` | RESULT ok (on: wall 129, fire 1, crater 4); one run `on_crater=0` | RESULT ok (on: wall 91, fire 1, crater 5) |
| `kaiju_truce`, `kaiju_clinch` | RESULT ok | RESULT ok |
| `kaiju_duel` | Gojira wins with 95 HP (19 %), twice | Gojira wins with 95, 100 |
| `kaiju_triangle` | allies win, Ghidorah dead at 59 and 63 s; Gojira 287, 227 | allies at 59 and 61 s; Gojira 170, 90 |
| `ghidorah_heads`, `ghidorah_fight`, `cthulhu_show` | exit 0, logs complete | exit 0, logs complete |
| `cthulhu_grab`, `cthulhu_intruder`, `cthulhu_kaiju`, `cthulhu_sea`, `cthulhu_spawns`, `cthulhu_swim`, `cthulhu_territory` | RESULT ok | RESULT ok |
| `cthulhu_ocean` | RESULT ok | RESULT FAIL: `idle_removed=5` (VoxeLibre's own removals, as before), once also `ashore=60.5` |
| `compat.sh` | step 2: three kaiju, three eggs | step 2: three kaiju, three eggs |

Path searches on VoxeLibre (`NAV` lines, 23 course runs): 0.9-2.0 ms on average per search, the
slowest search of a run 1.8-4.2 ms (7.3 ms once, with other scenarios running in parallel);
4-30 searches per course. `kaiju_triangle`: 39 searches, 0.9 ms on average, 2.6 ms at most.
`gojira_smash`: 3 searches (1 partial, 2 without a path), 2.2 ms on average, 4.2 ms at most.

### Results after the reach, ceiling and knockback changes (16 Nov 2026)

Gojira's bite along his body and breath from where the bite ends (up to 48 nodes upwards),
flyers under roofs, Ghidorah's landing spots, and the bite's knockback on players on
VoxeLibre. Luanti 5.17, `vendor/mineclonia`, VoxeLibre 0.92.4, the installed Mineclonia for
the new scenarios; up to five clients in parallel.

**Balance** (Gojira's change only; acceptance: he wins every duel, median 90-105 HP, no run
outside 50-175; the allies win the triangle with Gojira alive). `breaths / close` are his
breaths and those started closer than 9 nodes, which he could not do before. No tuning was
needed.

| Run | Mineclonia (vendor) | VoxeLibre 0.92.4 |
|---|---|---|
| `kaiju_duel`, gap 20 | Gojira 95 (100 s, 1 / 0), 90 (102 s, 1 / 0) | 100 (98 s, 1 / 0) |
| `kaiju_duel`, gap 30 | 95 (101 s, 1 / 0), 100 (100 s, 1 / 0) | 100, 100 (99 s, 1 / 0) |
| `kaiju_duel`, gap 44 | 95 (103 s, 2 / 1), 90 (104 s, 1 / 0) | 100 (100 s, 1 / 0) |
| `kaiju_duel`, median | 95 | 100 |
| `kaiju_triangle` | allies, Ghidorah dead at 59, 61, 61, 61, 56 s; Gojira 249, 244, 297, 288, 281; Mothra 254, 215, 203, 242, 305; 5 / 3-4 each | allies at 60, 59, 60 s; Gojira 127, 191, 126; Mothra 248, 263, 284; 5-6 / 4-5 |

Before the change, with the same counters: duel (gap 30) 95 HP, 1 / 0; triangle Gojira 216,
4 / 0. In the triangle his close breaths come when Mothra's gust pushes Ghidorah just out
of his bite; the fight is as long as before.

**New scenarios and regressions.** "old code" is the commit before the change concerned.

| Scenario | Mineclonia (vendor) | VoxeLibre 0.92.4 | Mineclonia (installed) |
|---|---|---|---|
| `kaiju_knockback` | RESULT ok (unchanged code path) | old code FAIL: Gojira 1.0 / 0, Ghidorah 0.9 / 0; now RESULT ok | RESULT ok |
| `kaiju_knockback`, `enable_damage = false` | RESULT ok | first gate FAIL: 0 / 0; now RESULT ok | RESULT ok |
| `gojira_reach` | old code FAIL (`ring`, `chest`, `high`); now RESULT ok (3 of 3 with the final scenario) | old code FAIL (the same three); now RESULT ok (2 of 2) | RESULT ok (2 of 2) |
| `mothra_ceiling` | old code FAIL (all three rooms left through the roof); now RESULT ok in 19 of 22 runs (see the notes) | old code FAIL (the same); now RESULT ok in 15 of 16 runs | RESULT ok |
| `ghidorah_ceiling` | old code FAIL (all three phases); now RESULT ok, 7 of 7 since the scenario waits for his target | old code FAIL (`low`; in `cavern` he left the loaded area and the client crashed once); now RESULT ok, 6 of 6 | RESULT ok |
| `kaiju_duel` (final code) | Gojira 95, 90 | 95, 104 | 95, 95 |
| `kaiju_triangle` (final code) | allies; Gojira 299, 232 | allies; Gojira 178, 61 | allies; Gojira 119 |
| `kaiju_fight` | Gojira 138-176 after 60 s, Mothras 350 / 145-212 | Gojira 136-165, Mothras 350 / 145-178 | not run |
| `gojira_overhead`, `kaiju_clinch`, `gojira_water` | RESULT ok | RESULT ok | not run |
| `gojira_anim`, `gojira_punch` | exit 0, logs as before (6.15 n/s; speed kept) | exit 0 (6.0 n/s; speed kept) | not run |
| `cthulhu_kaiju`, `cthulhu_grab`, `cthulhu_territory` | RESULT ok | RESULT ok (`cthulhu_intruder` too) | not run |
| `mothra_terrain` | as before: 0 samples in the wall, 10.75 above it, husk dead, lands | 0 samples, 10.66 above it, husk at 3 HP, lands | not run |
| `kaiju_truce`, `kaiju_truce_end`, `kaiju_dead_reload`, `kaiju_settings` | RESULT ok | RESULT ok; `kaiju_truce` once "gojira3 was not on a path at the kill (rerun)" in 2 of 7 runs (the scenario's own precondition; he was 31 and 46 nodes from Ghidorah then, probably breathing fire: not checked) | not run |
| `ghidorah_fight`, `ghidorah_heads`, `ghidorah_show`, `mothra_show` | exit 0, logs complete | exit 0, logs complete | not run |
| `compat.sh` | step 2: three kaiju, three eggs | step 2: three kaiju, three eggs | not run |

Notes on the failures and oddities:

- `mothra_ceiling`: the one failing run on Mineclonia had `cave_min_roof_gap=0.3` (she was
  1.7 nodes above her cap for a moment, not in the roof), with five clients in parallel, one
  of them generating a v7 world. Not seen again in 12 runs with a log line for it; the
  likeliest cause is one long server step (the climb is stopped at the cap once a step). The
  one on VoxeLibre: 9 samples `inside` in the low hall without leaving it, not seen again in
  10 runs with a log line for it; not explained. Two more Mineclonia runs failed only because
  she never crossed the lava pool, which was a 16 × 16 pool beside her start then.
- `ghidorah_ceiling`: before the scenario waited for his target, one Mineclonia run failed
  `low_walked` because he found the player only after the phase was over.
- `gojira_reach`: one run each failed on a criterion that depended on chance and was made
  firmer: `ring_first_dist=9.9` (he had walked off again when the breath was released), and
  `ring_burned` on the installed Mineclonia (one breath, no flame hit the player; the phase
  now has time for three).
- Clearance checks (`FLIGHT` lines of `mothra_ceiling`): 15-20 rays per check on average, 40
  at most. One client alone: 0.12-0.13 ms per check, 0.6-0.7 ms at most. Five clients in
  parallel: 0.2-0.5 ms on average; the slowest check of a run 1.4-6.6 ms in 11 of 15 runs,
  18-25 ms in three and 688 ms in one (wall-clock time of a loaded machine).

**One run in a real Nether** (not a repository scenario; mapgen v7, seed 7, both games): the
scenario looks for the tallest dry cavern column near (0, 0) of the Nether (68 and 74
nodes high), lets the creative player hover in mid-cavern (on the floor the cavern's top is
outside the active blocks, and the kaiju up there were unloaded), and spawns a Ghidorah on
the floor and a Mothra above him. They fight for about a minute, until she is dead.

- Mothra: never inside a node (0 of about 3000 samples per run), at least 2 nodes under the
  roof, mostly flying right at her cap while he flies; over lava and floor at least 8 nodes
  up while alive. In the first run she touched the roof once (2.1 nodes above her cap):
  `fly_velocity` now stops the climb at the cap, after which she was at most 0.3 above it.
- Ghidorah takes off (the cavern is high enough), stays 2-6 nodes under the roof, and lands
  on netherrack, soul sand and crimson nylium. In the first runs he took the cap of a huge
  crimson fungus above him for a roof and landed again at once, and flew through such caps
  (10-24 samples "inside" `mcl_nether:nether_wart_block`): wart blocks and shroomlights now
  count as foliage, like leaves (no roof, no landing ground, flown through). After that:
  0 samples inside on VoxeLibre; on Mineclonia the 24 samples in a fungus cap he took off
  through remain, by design. Once, after her death, none of his 9 landing spots among the
  fungi passed and he came down where he was: on top of a fungus cap.
- Clearance checks there: 15-17 rays on average, 0.15-0.22 ms, 0.7-1.7 ms at most (8.9 ms
  once).
- Not looked at: the nether's lava sea (the caverns found were dry below the kaiju), narrow
  tunnels, a nether fortress, and players as targets.

### Results after the VoxeLibre parity and Ghidorah combat changes (16 Nov 2026)

VoxeLibre: Mineclonia's gravity and environment damage, the parrot's hurt sound. Both
games: Gojira stands through his bite; Ghidorah's beams pass through small mobs and deal 1
per head to players; side-head volleys at a melee target with his bite at 10; smashing in
the air. Luanti 5.17, `vendor/mineclonia`, VoxeLibre 0.92.4; two clients in parallel.

**Balance** (Gojira's HP left of 500 in the duel; acceptance as before: he wins every
duel, no run outside 50-175; the allies win the triangle with Gojira alive). No tuning
after the first values (volley 1 per head and tick every 12 s, bite 10).

| Run | Mineclonia (vendor) | VoxeLibre 0.92.4 |
|---|---|---|
| Before: `kaiju_duel`, gap 30 | 95, 95 (101 s) | 100, 100 (99 s) |
| Before: `kaiju_triangle` | allies at 62 s; Gojira 215, Mothra 293 | allies at 57 s; Gojira 231, Mothra 275 |
| After the VoxeLibre and bite changes: duel, gap 30 | 90 (102 s) | 100 (99 s) |
| After those: triangle | allies at 59 s; Gojira 299, Mothra 239 | allies at 59 s; Gojira 294, Mothra 233 |
| After all: `kaiju_duel`, gap 30 | 92, 89, 112, 80 (96-101 s) | 84, 84, 84, 84 (99 s) |
| After all: gap 20 | 80 (100 s) | 84 (98 s) |
| After all: gap 44 | 100 (102 s) | 84 (100 s) |
| After all: `kaiju_triangle` | allies at 57, 58, 60, 61 s; Gojira 314, 272, 216, 228; Mothra 242, 254, 197, 203 | allies at 56, 58, 60, 59 s; Gojira 285, 288, 282, 286; Mothra 254, 236, 278, 278 |

**Scenarios** on the final code (both games unless noted): `RESULT ok` for
`ghidorah_ceiling`, `gojira_reach`, `mothra_ceiling`, `kaiju_knockback`, `cthulhu_sea`,
`nav_wall`, `nav_wall_wide`, `nav_cliff`, `nav_forest`, `nav_water`, `nav_protected`,
`nav_far`, `nav_pace`, `kaiju_clinch`, `kaiju_settings`, and the six new ones
(`kaiju_physics`, `kaiju_env`, `gojira_bite`, `ghidorah_beam`, `ghidorah_sidemain`,
`ghidorah_airsmash` with its two extra runs). `ghidorah_fight` and `kaiju_fight` (no
RESULT line) ran as described; in one `ghidorah_fight` run on Mineclonia he stood in a
blast crater 3 nodes below the player, where the side heads can reach a player in melee,
and fired a volley at him.

`gojira_smash`: Mineclonia `RESULT ok`. VoxeLibre `RESULT FAIL: gold=0; emerald=0`: the
chest stayed in 3 of 3 runs (one was cut short by the 180 s cap), and also with the code
from before these changes in a run on the same day: the
pathfinder now leads him around the forest and into the ring from the east, past the house
with the chest (earlier runs: no path, and a straight bulldoze through it). Which of the
two happens depends on how far the 4 ms search gets; the scenario's chest check assumes
the straight line.

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

### `mothra_ceiling`: Mothra under a roof

- **Settings:** creative, `viewing_range = 160`, `mobs_spawn = false`. Depends on `mothra,
  kaiju_test`.
- **Scene:** three closed rooms on the flat world, built one after the other with
  `kaiju_test.fill` after their area is generated: floor at y = 8.5, walls 1 node thick, a roof 3
  nodes thick. The player stands in a corner. A Mothra is spawned in the middle and wanders
  for 20 s:
  - `cave`: 64 × 64, stone, the roof 22 above the floor; she starts at y = 14.
  - `low`: 40 × 40, the roof 6 above the floor (she is 3.6 tall and needs 5.6); she starts
    1.2 above the floor.
  - `nether`: 48 × 48, netherrack, a bedrock roof 28 above the floor, a 32 × 32 lava pool in
    the middle of the floor; she starts above it at y = 22.
- **Logs:** `<room>: inside at …` the first time her feet or the top of her body are in a
  walkable node; `<room>: end at …`; `FLIGHT refreshes=… rays=… (… per refresh, max …) avg_us=…
  max_us=…` (`kaiju_core._flight_stats`); `VALUES <room>_inside, _escaped, _min_roof_gap,
  _min_floor_gap, _max_rise, _moved` for each room, `nether_min_lava_gap`, `max_rays`;
  `RESULT …`.
- **Runtime:** about 80 s.
- **Good:** `RESULT ok`: in every room `inside = 0` and `escaped = false`; `cave` and `nether`
  keep at least a node to the roof (measured 1.7-1.9 and 2.5-7); `low_max_rise ≤ 1` (she stays
  at 1.0 above the floor, 1.2 under the roof); over the lava she is at least 5 nodes up
  (measured 15-21); she moves (`cave_moved ≥ 8`, `low_moved ≥ 4`); `max_rays ≤ 40`. The times
  are logged, not checked: with other clients running they jump (see the results below).
- Before the change she left all three rooms through the roof on both games (`inside` 60-77
  samples per room, `escaped=true`, ending 20-40 nodes above the roofs).
- The walls are one node thick on purpose: the first version of the check looked at the
  samples only, 4 nodes apart, and she flew through the walls between them.

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
  `gojira, mcl_chests, mcl_beehives, kaiju_test`.
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
  6 s later. The report at 60 s ends with `VALUES gold=… emerald=… floating_sand=…
  wall_removed=… trunks_removed=… nav_max_us=…` and `RESULT ok`: 17 gold ingots and 5 emeralds
  on the ground, no floating sand, at least 80 stone nodes of the ring and 12 trunks gone
  (lower bounds: the counts depend on his route), and on VoxeLibre no path search over 20 ms.

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

- **Settings:** survival, `viewing_range = 140`, `fov = 80`. Depends on `gojira`, `kaiju_test`.
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
  The last lines are `VALUES y=… pillar=…` and `RESULT ok`: at t=30 he is out of the water
  (`y` ≥ 4.4) and within 10 nodes of the pillar (`pillar`, horizontally), not in a tunnel
  below the pools. VoxeLibre passed 4 of 4 runs (y 7.5-8.5, 0.2-4.5 nodes from the pillar).
  On Mineclonia the moment is too early or too late in half the runs (3 of 6 ok): at t=30
  he is sometimes still climbing out (y 2.5, 3 nodes from the pillar) and sometimes already
  past it (13 and 22 nodes, on the ground). Read the `t=` lines before calling that a failure.

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

### `kaiju_knockback`: a kaiju's bite throws a player, on both games

- **Settings:** survival, `viewing_range = 140`, `mobs_spawn = false`. Depends on `gojira,
  ghidorah, kaiju_test`.
- **Scene:** the player stands at (0, 9, −10), HP topped up every step. A Gojira without any AI
  (`attack_type = false`, no targeting rules, no `ai_functions`) is spawned 5 nodes away; the
  scenario sets `e.attack = player` and calls `e:custom_attack()` once. Then the same with a
  Ghidorah 6 nodes away. For 1.5 s after each bite the player's largest horizontal displacement
  and rise are taken.
- **Logs:** `enable_damage = …`, `VALUES gojira_player_flat=… gojira_player_rise=…
  ghidorah_player_flat=… ghidorah_player_rise=…`, `RESULT …`.
- **Runtime:** about 15 s.
- **Good:** `RESULT ok`: Gojira (`_attack_knockback = 3`) moves the player at least 5 nodes and
  lifts him at least 1; Ghidorah (0) 0.5 to 4 nodes and at least 0.3 up. Measured: 6.2 (or
  16.6, see below) / 1.5 and 1.3 / 0.6 on both games. Before `vl.lua` had Mineclonia's knockback, VoxeLibre gave 1.0 / 0 and
  0.9 / 0 (the engine's knockback only).
- **Second run, without damage:** `KAIJU_TEST_CONF='enable_damage = false' tests/run.sh
  kaiju_knockback`. Mineclonia throws the player all the same (its gate is the punch's raw
  damage, not the HP lost). VoxeLibre with the layer's first gate ("the bite took HP"): 0 / 0,
  a play-test finding; with Mineclonia's gates the same as Mineclonia.
- Gojira's throw comes out as either 6.2 or 16.6 nodes, on both games and with or without
  damage (about half of the runs each); the rise is 1.5 in both. Which one is not understood:
  the velocity given is the same, and the player's movement is computed by the client.
- Not covered: a raised shield, creative mode, mobs as victims (they keep each game's own
  knockback).

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

### `ghidorah_ceiling`: roofs, a blocked flight, and where he lands

- **Settings:** survival, `viewing_range = 160`, `mobs_spawn = false`, **`kaiju_smash_blocks =
  false`** (nothing clears his way or his landing spot). Depends on `ghidorah, kaiju_test`.
- **Scene:** three phases at z = 0, 200 and 400. Each clears the flat world's trees, builds its
  scene, pins the survival player at (60, 9, z) (HP never below 1) and spawns a fresh Ghidorah at
  (0, 8.6, z): 60 nodes away, beyond `FAR_TARGET`, so he wants to fly. A phase's time runs from
  the moment he has his target (on Mineclonia that sometimes takes several seconds).
  - `low` (15 s): a stone roof 18 nodes above the floor over both of them. He is 15 tall and
    needs 21 to take off.
  - `cavern` (30 s): a roof 40 above the floor; between x = 25 and 45 it hangs down to 16 above
    the floor, across the whole width: high enough to walk under, too low to fly under (17).
  - `forest` (30 s): open sky. Over his start a canopy of leaves 17 above the ground (with a
    few trunks in it, away from his column, or the leaves decay). Around the player low trees
    every 4 nodes (trunk 3, leaves on top: he sees the player over them), except a treeless
    patch of 17 × 17 around the player and a 10 × 10 clearing 12 nodes west of him; both have
    a netherrack floor.
- **Logs:** every 3 s `<phase>: pos=… flying=… land=… target=…`; `<phase>: take-off at …`,
  `<phase>: touch-down at …`, `<phase>: end at …`; `VALUES low_takeoffs, low_inside, low_max_top,
  low_walked, cavern_takeoffs, cavern_inside, cavern_max_top, cavern_flying, forest_takeoffs,
  forest_inside, forest_landing_trees, forest_landing_node, forest_clearing_dist`; `RESULT …`.
- **Runtime:** about 100 s, up to 160 s when he is slow to find his target.
- **Good:** `RESULT ok`:
  - `low`: no take-off, never inside a node, and he walks (`low_walked ≥ 10`, measured 50-57:
    he reaches the player).
  - `cavern`: 1 or 2 take-offs in 30 s, never inside a node, the top of his body below y =
    47.5 (measured 29), on the ground at the end. He takes off, the first clearance check
    finds the low section in the way, and he comes down after a hop; on foot for 20 s
    (`_no_fly`) he walks under the section. A second take-off happens when the melee's stuck
    detection asks for one near the player; it ends the same way.
  - `forest`: he takes off through the leaves, and his first touch-down is on netherrack with
    no trunk or leaf node in his body box (`forest_landing_trees = 0`). `forest_clearing_dist`
    (logged) is 0.5-0.8 when it is the clearing.
- Before the change, on both games: `low_takeoffs=1` (through the roof; he landed on top of
  it, `low_inside` 22-43); in `cavern` he flew up through the roof (`cavern_max_top=81`,
  `cavern_inside=39`) and left the loaded area; in `forest` he came down on the trees
  (`forest_landing_trees` 16-54 or the landing node a leaf).
- `forest_inside` counts the canopy he flies through (leaves are walkable nodes) and is not
  checked.

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
  gojira=<hp> mothra=<hp> ghidorah=<hp> breaths=N close=N up_far=N` (Gojira's breaths, as in
  `kaiju_duel`), and 8 more samples.
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
  winner=gojira|ghidorah|draw|none t=N gojira=<hp> ghidorah=<hp> gap=N breaths=N close=N
  up_far=N`: Gojira's breaths, those started closer than 9 nodes (feet to feet, the old
  minimum) and upward ones from beyond 32 (the old maximum). The setting `kaiju_duel_gap`
  fixes the gap (`KAIJU_TEST_CONF`, §Usage).
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
  4.7 nodes horizontally; 5.8 nodes up that is 7.5 in 3D from his feet. When the bite was
  measured from his feet (reach 7) he had to close in to about 3.9, and with the 3D check in
  `kaiju_core`'s `at_standoff` reverted he stood at `flat=4.4 dist=7.3` with `bites=0` for the
  whole run. Since his bite is measured from his body's axis (`_bite_height`), the player is in
  reach at the standoff gap and he bites from there (`gojira_reach` has the same at 8 nodes up).

### `gojira_reach`: no gap between bite and breath; flyers up to 48 nodes

- **Settings:** survival, `viewing_range = 140`, `mobs_spawn = false`. Depends on `gojira,
  kaiju_test`.
- **Scene:** four phases, each with a fresh Gojira at (0, 8.6, 20) and the player pinned at
  (0, 8.5 + h, −10) (`gravity = 0`, put back when knocked away, HP topped up):
  - `ring` (h = 1, 24 s: time for three breaths, as not every breath hits a player): the player stands on an obsidian node inside an obsidian ring of
    radius 5, 3 nodes high. Obsidian is immune to smashing, so the ring stops Gojira 7.9 nodes
    away: beyond his bite (7), inside the old shortest breath (9). His breath is held back
    (`_breath_cooldown = 1e9`) until he has been within 8.7 nodes for a second and is still
    that close, or he would breathe on the way (or from 9.9 nodes, when he walks off again
    to look for a way around the ring).
  - `chest` (h = 8, 14 s), breath off: the player hovers at chest height.
  - `head` (h = 26.5, 12 s): 12 nodes above his head.
  - `high` (h = 40, 18 s).
- **Logs:** per breath `<phase>: breath at dist <3D, feet to feet>, flat <horizontal>, up=…`;
  per phase `<phase>: end, flat …, dist …`; `VALUES <phase>_breaths, _breaths_up, _first_dist,
  _bites, _burned, _gojira_hp` for each phase; `RESULT …`.
- **Runtime:** about 95 s.
- **Good:** `RESULT ok`:
  - `ring_breaths ≥ 1` with `ring_first_dist` between 7 and 9 (measured 7.9-8.1), and
    `ring_burned` (a flame set the player on fire);
  - `chest_bites ≥ 1` (measured 6-7: he stops below the player and bites);
  - `head_breaths_up ≥ 1`;
  - `high_breaths_up ≥ 1` and `high_burned`: he starts at 48.0 nodes (`BREATH_UP_MAX_DIST`)
    and again from below at about 40;
  - `<phase>_gojira_hp = 500` in every phase: his flames don't hit himself.
- Before the change (both games): `ring_breaths=0`, `chest_bites=0`, `high_breaths_up=0`.
  With the new reach but the old flame lifetime, `high_burned` failed on Mineclonia in 4 of 4
  runs: the flames' 80 server steps ended after 42 nodes in the test client (0.024 s per
  step). `shoot_flame` now gives every flame at least 3 s.

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
  `gojira, ghidorah, mcl_fire, kaiju_test`.
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
  `on` must be above zero in all three; the exact numbers vary. The last lines are
  `VALUES off_wall=… off_fire=… off_crater=… on_wall=… on_fire=… on_crater=…` and `RESULT ok`
  for exactly that. `on_crater` was 0 in one Mineclonia run of four (the volley missed the
  counted ground while four scenarios ran in parallel): rerun it alone.

### Navigation courses: `nav_wall`, `nav_wall_wide`, `nav_cliff`, `nav_forest`, `nav_water`, `nav_protected`, `nav_far`, `nav_pace`

Eight short courses for the walking kaiju's pathfinding: something stands between the kaiju
and the player that he may not break, and there is a way around it. They define what
"the same navigation on both games" means: every course must end with `RESULT ok` on
Mineclonia (its own pathfinder) and on VoxeLibre (`kaiju_core/vl_path.lua`). Times and
routes differ and are not compared.

All use `kaiju_test.nav_course` (`tests/lib/init.lua`): the area is made flat (dirt up to
y = 8, air above), the course is built, the kaiju is spawned with `view_range` 80, and from
the moment he has his target his position is sampled every 0.25 s. The course ends 0.3 s
after he is within `reach + 1` of the player (his bites knock the player away), or after
its time limit.

- **Settings:** survival, `mobs_spawn = false`, `kaiju_gojira_fire = false`, and
  `kaiju_smash_blocks = false` except in `nav_protected`. Gojira's breath is disabled
  (`_breath_cooldown = 1e9`). Depend on `gojira` (`nav_wall_wide`: `ghidorah`) and
  `kaiju_test`.
- **Logs:** `start: <mob> at <pos>, player <n> nodes away`, every 2 s
  `t=… pos=… y=… dist=… waypoints=<n|nil> bulldoze=<bool>`, on VoxeLibre
  `NAV plans=… partial=… failed=… avg_us=… max_us=…`, then `VALUES …` and `RESULT …`.
- **Values:** `reached` (seconds until he is in reach), `speed` (nodes/s up to then),
  `removed` (course nodes gone), `moved` (path length), `max_y`, `nav_max_us` (VoxeLibre:
  the slowest path search, µs; Mineclonia: 0), and per course `top` or `ashore`.
- **Runtime:** 15-70 s.

| Course | Scene | Good (`RESULT ok`) |
|---|---|---|
| `nav_wall` | Cobble wall, 3 high, x −20..20 at z = 0, with a 7-wide gap at x 4..10. Gojira at (0, 14), player at (0, −12). | `reached` within 60 s, `removed` = 0 |
| `nav_wall_wide` | The same wall with a 9-wide gap at x 4..12, for King Ghidorah (7 × 7 nodes), kept on the ground and without beams (`_mode_timer`, `_beam_cooldown` = 1e9; `kaiju_ghidorah_beam_blasts = false`). | `reached` within 60 s, `removed` = 0 |
| `nav_cliff` | Stone plateau, 6 high, z ≤ −6, the player on top at (0, −16); a 7-wide stair of 1-node steps at x 4..10. | `top` (on the plateau, y ≥ 14.4) and `reached` within 50 s, `removed` = 0 |
| `nav_forest` | Trunks every 3 nodes under a closed canopy, x −16..16, z −9..13, with a clear 7-wide lane at x 6..12. Built once he has his target (the canopy hides the player). Gojira at (0, 24), player at (0, −18). | `reached` within 45 s, `removed` = 0 (trunks and leaves) |
| `nav_water` | Pool 31 × 31, 22 deep, vertical stone walls, one 7-wide ramp of 1-node steps at x 4..10. Gojira swims at (0, 30), player on land at (0, −6). | `ashore` (immersion 0, y ≥ 8.4) and `reached` within 60 s, `removed` = 0 |
| `nav_protected` | As `nav_wall`, but block smashing is on and the wall is protected (`core.is_protected` overridden for its box). | `reached` within 60 s, `removed` = 0 |
| `nav_far` | Open ground, the player 60 nodes away (VoxeLibre's search sees 24: he gets there on chained partial paths). | `reached` within 20 s, `speed` ≥ 5 (of his 6) |
| `nav_pace` | No target (`view_range` 0). Gojira paces all the time (`pace_chance` 1, `pace_width` 14) in a pen of cobble walls, 21 × 21 inside. | `moved` ≥ 10, `max_y` ≤ 8.9 (on VoxeLibre a kaiju that runs into a wall hops), `removed` = 0 |

How the courses got their shape (16 Nov 2026): they were written first and run on Mineclonia.
The first versions had the gap, the stair and the ramp 11 to 19 nodes off the direct line;
Mineclonia failed `nav_wall`, `nav_wall_wide`, `nav_cliff` and `nav_water` there. Its
pathfinder stops after 10 ms, which for a body 5 nodes wide is a small area, so it led
Gojira straight to the wall, where he was stuck, bulldozed, and stood again. With a
2-high wall it failed even with the gap at x 4..10 (passed only after a bulldoze had
pushed him sideways). So the walls are 3 high and every opening is 7 nodes from the
direct line; that Mineclonia passes, in 5-9 s when the machine is idle and up to 38 s
(`nav_wall_wide`, after one or two bulldozes) with other scenarios running in parallel.
Wider detours are beyond both games' kaiju and end in the bulldozer.

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

### VoxeLibre parity and Ghidorah in combat: `kaiju_physics`, `kaiju_env`, `gojira_bite`, `ghidorah_beam`, `ghidorah_sidemain`, `ghidorah_airsmash`

Six short scenarios, each ending with `VALUES …` and `RESULT ok` or `RESULT FAIL: …`. All
depend on `kaiju_test`; all failed before the change they belong to (16 Nov 2026).

| Scenario | Scene | Good (measured, Mineclonia / VoxeLibre) | Before |
|---|---|---|---|
| `kaiju_physics` (10 s) | A passive Ghidorah on flat ground gets Mothra's gust: `add_velocity(22, 6, 0)`. Time above the ground and drift within 2 s. | `air` 0.25-0.55 s, `drift` 5-8.5 nodes (0.3 s, 5.9 / 0.3 s, 6.6) | VoxeLibre 0.8 s, 9.2 (gravity 14.7) |
| `kaiju_env` (12 s) | Passive, pinned kaiju, smashing off: Mothra and a Gojira over lava sources; a Gojira and a Ghidorah with a cobble column inside the body up through the head. HP lost in 4 s. | `mothra_lava` ≥ 16 (35 / 35), `gojira_lava` 0, `gojira_wall` 4-12 (8 / 8), `ghidorah_wall` 0 | VoxeLibre: 0 everywhere |
| `gojira_bite` (30 s) | Survival player (kept alive) 30 nodes away, breath off; Gojira chases and bites for 25 s. Distance he moves while the `punch` clip plays. | `per_bite` ≤ 1.5 nodes with at least 3 bites (0.4 / 0.6, 6 bites) | 3.6 / 4.2 per bite |
| `ghidorah_beam` (35 s) | Ghidorah pinned 20 nodes from a pinned survival player; the HP lost per volley. `bare`: all heads, no armour. `cow`: side heads severed, a cow held on the centre head's line; the left stump's hit box against the neck joint. `iron`: all heads, full iron armour. | `bare` 16-30 (24 / 24), `cow_hurt` ≥ 6 (24), `behind_cow` 3-12 (8 / 8), `stump_off` ≤ 0.5 (0.0), `iron` 4-30 (10 / 8) | `bare` 72, `behind_cow` 0, `stump_off` 1.8 |
| `ghidorah_sidemain` (60 s) | Gojira and Ghidorah in melee for 40 s (both kept alive, the player 55 nodes away), then Gojira removed and the survival player pinned 5 nodes in front of Ghidorah for 14 s. Counts volleys with `_beam_side == "main"`. | `main_volleys` 2-5 (3 / 3), `main_damage` ≥ 1 (48 / 48), `player_volleys` 0, `target` player | no main volleys |
| `ghidorah_airsmash` (50 s) | A survival player on a realm barrier 15 nodes up (not pointable, so "in the air" for him); Ghidorah circles it for 45 s. Across the circle: a cobble wall 25 high, a band of oak leaves with trunks, a stone ridge 8 high. Beam blasts off. Also logs the time of a smash pass in the air. | `wall_removed` ≥ 30 (288 / 264), `wall_y` ≤ 27 (25.6 / 25.5: through it), `leaves_removed` ≥ 10 (553 / 530), `stone_removed` 0, `ridge_y` ≥ 26 (30.2: over it) | nothing removed, `wall_y` 47 |

`ghidorah_airsmash` has two more runs:
`KAIJU_TEST_CONF='kaiju_smash_blocks = false' tests/run.sh ghidorah_airsmash` (nothing is
removed and he flies over the wall, `wall_y` ≥ 40: 47.8 / 46.5) and
`KAIJU_TEST_CONF='kaiju_test_protect = true' …` (the scenario protects the wall: it stays
and he flies over it, 47.6 / 46.9, while the leaves still fall). A smash pass in the air
took 4.6 ms (Mineclonia) and 2.0 ms (VoxeLibre) on average; one pass on Mineclonia took
212 ms, when a whole canopy went at once.

`ghidorah_heads` now also logs Gojira's distance and, at t = 40, `COUNTS side=N
melee_full=M`: the samples after t = 8 in a side volley, and in a full volley at a Gojira
closer than 10 nodes. It is not a pass/fail line, because the brawl takes a different
course every run. Nine runs after the changes: Mineclonia `side` 4, 7, 10, 6, 6 with
`melee_full` 0 in all; VoxeLibre `side` 8, 8, 9, 13, 0 (he flew after Mothra for the whole
run) with `melee_full` 0, 5, 0, 0, 0 (twice Mothra's gust threw him 12 nodes off and Gojira
breathed fire from there instead of walking back in). On VoxeLibre before the gravity
change: `side` 0, `melee_full` 1.

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
     `column`, `on_ground`, `count_removed`, `fill` and `count` (nodes in a box), `nav_course`
     (§Navigation courses) and `result` (the `VALUES` and `RESULT` lines from a table of
     values and a list of expected ranges).
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
