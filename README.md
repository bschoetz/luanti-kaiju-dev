# Kaiju for Mineclonia and VoxeLibre: development

This is the development repository of the Luanti modpack **Kaiju**: giant monster mobs
(Gojira, Mothra, King Ghidorah, Cthulhu) for [Mineclonia](https://codeberg.org/mineclonia/mineclonia)
and [VoxeLibre](https://content.luanti.org/packages/wuzzy/mineclone2/) on
[Luanti](https://www.luanti.org/) 5.10 or newer. It holds the full source with the developer
documentation, the Blender and PIL generators for the models and textures, and the headless
test harness.

To **play**, use [luanti-kaiju](https://github.com/bschoetz/luanti-kaiju): the modpack
alone, with a player README and screenshots. That repository is generated from this one
by `tools/publish.sh`.

The mods are built on Mineclonia's `mcl_mobs` framework; on VoxeLibre a compatibility layer in
`kaiju_core` provides that part of it (limitations in
[`kaiju/README.md`](kaiju/README.md#voxelibre)).

| Mod in `kaiju/` | What it is |
|---|---|
| [`kaiju_core/`](kaiju/kaiju_core/README.md) | Shared library (no mob of its own): block smashing, bulldozing, wading, knockback fix, death handling, flight helpers, hit boxes for arrows, the truce after a Ghidorah dies, settings, the VoxeLibre layer. Required by every kaiju. |
| [`gojira/`](kaiju/gojira/README.md) | Gojira: a 15-node fire-breathing kaiju that hunts players and smashes through forests, houses and hills. |
| [`mothra/`](kaiju/mothra/README.md) | Mothra: a giant guardian moth, neutral to players, that hunts Ghidorah, Gojira and monsters from the air. |
| [`ghidorah/`](kaiju/ghidorah/README.md) | King Ghidorah: a three-headed dragon that walks and flies, with gravity beams and regrowing heads. |
| [`cthulhu/`](kaiju/cthulhu/README.md) | Cthulhu: an amphibious sea monster that sleeps on the sea floor, defends a territory, grabs intruders and drags them under water. |

## Layout

| Path | Contents |
|---|---|
| `kaiju/` | The modpack: `modpack.conf`, `settingtypes.txt`, `README.md` and the five mods, each with a developer README (stats, architecture, tunables, model pipeline, known limitations). This is the folder a player installs. |
| `tools/` | `<mob>_model.py` builds `kaiju/<mob>/models/<mob>.glb` in headless Blender, `<mob>_texture.py` builds `kaiju/<mob>/textures/<mob>.png` with PIL. `publish.sh` and its templates in `tools/publish/` generate the public repositories. |
| `tests/` | Headless end-to-end scenarios run in a real Luanti client under Xvfb, and `compat.sh`, the upgrade check. See [`tests/README.md`](tests/README.md). |
| `vendor/` | Not in the repository (git-ignored): shallow clones of the game and the engine, see below. |

To install the working copy for playing, link or copy `kaiju/` into your mods folder and
enable the **Kaiju** modpack in the world:

```sh
ln -s "$PWD/kaiju" ~/.minetest/mods/kaiju     # or: cp -r kaiju ~/.minetest/mods/
```

## Models and textures

The models and textures are generated; don't edit the `.glb` and `.png` files by hand.
Run from the repository root (Blender, Python 3 with Pillow):

```sh
blender -b --factory-startup --python tools/gojira_model.py -- kaiju/gojira/models/gojira.glb
python3 tools/gojira_texture.py kaiju/gojira/textures/gojira.png
```

and the same with `mothra`, `ghidorah` and `cthulhu`. Each mob's README has a "Model and
texture pipeline" section: bones, animation frames, the texture atlas, and the numbers the
scripts print to check themselves.

## Tests

Needs `luanti` (5.10+) on `$PATH`, `xvfb-run`, and ImageMagick for screenshots. The game
comes from `vendor/` by default:

```sh
git clone --depth 1 https://codeberg.org/mineclonia/mineclonia.git vendor/mineclonia
git clone --depth 1 https://github.com/luanti-org/luanti.git      vendor/luanti   # engine source, for reading
```

```sh
tests/run.sh kaiju_duel                 # Mineclonia from vendor/mineclonia
tests/run.sh mothra_show 30             # plus 30 screenshots
LUANTI_GAME=mineclone2 LUANTI_GAME_PATH=~/.minetest/games tests/run.sh kaiju_duel   # VoxeLibre
LUANTI_GAME=mineclonia LUANTI_GAME_PATH=~/.minetest/games tests/run.sh kaiju_duel   # an installed Mineclonia
tests/compat.sh                         # upgrade from the old four-folder layout
```

`LUANTI_GAME` is the game id (a folder in `LUANTI_GAME_PATH`; VoxeLibre's is `mineclone2`).
Each run gets its own folder under `tests/out/` with the log, the `[test]` lines and the
screenshots, and an isolated `HOME`, so your own Luanti settings and worlds are not touched.
A run fails on any `ERROR[` line; the self-checking scenarios end with `RESULT ok` or
`RESULT FAIL`. What a good run of each scenario looks like, the latest results on both
games, and the harness's quirks are in [`tests/README.md`](tests/README.md).

## Publishing

```sh
tools/publish.sh             # build gh/luanti-kaiju and gh/luanti-kaiju-dev, show git status
tools/publish.sh --commit    # and commit in both: "build from dev@<short sha>"
tools/publish.sh --no-shots  # keep the existing screenshots
```

`publish.sh` builds both repositories from the committed state (`git archive HEAD`) and
refuses to run while `kaiju/`, `tools/` or `tests/` have uncommitted changes. `gh/` is
git-ignored; each target in it is a git repository of its own, created on the first run and
otherwise emptied (except `.git`) and refilled, so a second run without a change in the
source shows no diff. It never pushes and adds no remotes.

- `gh/luanti-kaiju/`: the modpack's runtime files (Lua, `mod.conf`, models, textures,
  `modpack.conf`, `settingtypes.txt`), plus `README.md`, `ROADMAP.md` and `.cdb.json` from
  `tools/publish/`, `LICENSE`, and `screenshots/`.
- `gh/luanti-kaiju-dev/`: `kaiju/`, `tools/`, `tests/` (without `tests/out`), this README,
  `LICENSE`.
- The screenshots are shot with the `tests/readme_shots` scenario (1280×720, Mineclonia from
  `vendor/` or `LUANTI_GAME_PATH`), the last frame of each scene, optimized with `pngquant`.
  They are only shot again when `kaiju/`, `tests/readme_shots`, `tests/lib` or
  `tests/run.sh` changed since the last shots (`gh/.shots-stamp`).
- The script fails if the output contains an e-mail address, an absolute `/home/` path, your
  git e-mail or home directory (also in binary files), or `.claude` and memory files.

## Contributing

Issues and pull requests go to this repository (`luanti-kaiju-dev`), never to
`luanti-kaiju`, which is overwritten on every publish. Player-facing bugs may also be
reported at [luanti-kaiju issues](https://github.com/bschoetz/luanti-kaiju/issues).

- Change the generator scripts, not the generated models and textures, and commit both.
- Keep the developer READMEs in step with the code; known limitations go into the mod's
  "Known limitations" section (and into `tools/publish/ROADMAP.md` when players notice them).
- Run the scenarios that cover your change on Mineclonia and, where the change touches the
  shared code, on VoxeLibre; write a scenario for new behaviour (`tests/README.md`,
  "Writing a new scenario").
- Changes to the published text go into `tools/publish/`, then `tools/publish.sh`.

## License

[MIT](LICENSE), for the code and the media; see [`kaiju/README.md`](kaiju/README.md#license).
