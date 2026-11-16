# Kaiju for Luanti

![Gojira, King Ghidorah, Mothra and Cthulhu at the beach](screenshots/1-hero.png)

Giant monsters for the [Mineclonia](https://codeberg.org/mineclonia/mineclonia) and
[VoxeLibre](https://content.luanti.org/packages/wuzzy/mineclone2/) games on
[Luanti](https://www.luanti.org/). Four kaiju, each with its own model, animations and way of
fighting, and they fight each other as well as you: Gojira, Mothra, King Ghidorah and
Cthulhu.

This is a fan project, made out of love for the old monster films. The names stay as they
are.

Contributions go to the development repository,
[luanti-kaiju-dev](https://github.com/bschoetz/luanti-kaiju-dev): this repository is
generated from it. Bugs and ideas: [issues](https://github.com/bschoetz/luanti-kaiju/issues).

## The kaiju

None of them spawns naturally. Take their spawn eggs from the creative inventory, or
`/giveme gojira:gojira`, `/giveme mothra:mothra`, `/giveme ghidorah:ghidorah`,
`/giveme cthulhu:cthulhu`. Give them room: Gojira is 15 nodes tall, Ghidorah 20.

### Gojira

![Gojira breathing fire on the beach](screenshots/2-gojira.png)

A 15-node, fire-breathing kaiju with 500 HP. He hunts players and iron golems, wades through
lakes and swims in deep water, and smashes through forests, houses and hills on his way,
while the ground he stands on stays intact. Chests he tramples drop their contents.

- **Bite:** 18 damage, reach 7 nodes.
- **Fire breath:** at targets 9 to 32 nodes away, about 18 flames of 2 damage that set you
  on fire for 6 s and ignite blocks. He breathes upwards at flying targets.
- Immune to fire, lava, falling and drowning. Punches and arrows don't push him back.

**Fighting him:** he outruns a sprinting player (6 nodes/s). Punches only do 40 % of their
damage, arrows do it all, and his chest and head have hit boxes of their own. Between 7 and
9 nodes from him he can neither bite nor breathe. Creative players and peaceful mode are
safe. Killed, he drops diamonds and bones.

### Mothra

![Mothra in flight over the sea](screenshots/3-mothra.png)

A giant guardian moth with a 26-node wingspan and 350 HP. She is neutral to players and
hunts King Ghidorah, then Gojira, then any monster, from the air.

- **Wing gust:** 12 damage and a hard shove, in a cone below and in front of her.
- **Scale powder:** poison and magic damage on everything below her.
- She never lands. She flies at most 60 nodes above the ground under her target.

**Fighting her:** don't. She only turns on a player who hits her, and only in survival.
Leave her to fight the other kaiju; two Mothras beat a Gojira. She drops string and
glowstone dust.

### King Ghidorah

![King Ghidorah firing gravity beams](screenshots/4-ghidorah.png)

A three-headed golden dragon, about 20 nodes tall, with 600 HP. He walks and flies, and hunts
Gojira, Mothra and players.

- **Gravity beams:** from each head, 3 damage per head four times a second, range 40 nodes.
  They blast small craters into what they hit.
- **Bite:** 13 damage on the ground.
- **Three heads:** each has 120 HP of its own. A head that runs out is severed and grows back
  after 30 s. While his main head fights one enemy, the side heads beam others on their own.

**Fighting him:** shoot the heads. He dies when his body runs out of HP **or** when all
three heads are off at the same time. Cover stops the beams until they blast it away.
Gojira and Mothra together beat him; Gojira alone wins narrowly. When he dies, the Gojiras
and Mothras around call a truce and go separate ways instead of fighting each other. He
drops gold blocks and diamonds.

### Cthulhu

![Cthulhu rising from the sea](screenshots/5-cthulhu.png)

A 13-node amphibious sea monster with 550 HP. Use his egg at the sea: he makes the nearest
deep water (15 nodes or more, within 48 nodes) his home and sleeps on the sea floor.

- **Territory:** whoever comes within 48 nodes of his home under the open sky, kaiju and
  animals included, wakes him. He rises, roars, and attacks.
- **Claw swipe:** 16 damage, reach 8.
- **Grab:** he seizes players and small mobs and holds them under water for up to 6 s.
- **Madness:** players near him get nausea, and within 12 nodes darkness.
- He heals in the sea and dives home when badly hurt. Under water no mob can target him.

**Fighting him:** lure him ashore. On dry land he takes 1.5 times the damage and gives up
after a while. A grab ends early once he has taken 25 damage. Leave his territory and he
goes back to sleep. He drops a heart of the sea, prismarine crystals and ink sacs.

## Installation

From ContentDB: coming later.

For now, download this repository (`git clone` or the zip from GitHub) into your mods
folder, so that you get `mods/luanti-kaiju/modpack.conf` (the folder name does not matter):

```sh
cd ~/.minetest/mods        # ~/.luanti/mods on newer installs
git clone https://github.com/bschoetz/luanti-kaiju.git
```

Then, in the main menu, select a Mineclonia or VoxeLibre world, **Select Mods**, enable the
modpack **Kaiju** (all five mods), and **Save**.

## Supported games

- **Mineclonia:** the game the kaiju are written and tested for.
- **VoxeLibre** (tested with 0.92.4): everything works, with these limitations:
  - no pathfinder: the kaiju walk straight at their target, smashing what is in the way;
  - simpler walking physics, and punches cause no knockback;
  - lava, fire, suffocation, drowning and falls don't hurt the kaiju (burning does);
  - griefing follows VoxeLibre's `mobs_griefing` setting for all kaiju;
  - Ghidorah uses the enderman's hurt sound.

## Settings

In the main menu under Settings → Content: Mods → Kaiju, or in `minetest.conf`. They apply
at once, also with `/set` in a running game.

| Setting | Default | Off means |
|---|---|---|
| `kaiju_smash_blocks` | `true` | Gojira, Ghidorah and Cthulhu break no blocks. They then get stuck in forests and towns. |
| `kaiju_gojira_fire` | `true` | Gojira's breath sets no blocks on fire. It still burns whoever it hits. |
| `kaiju_ghidorah_beam_blasts` | `true` | Ghidorah's beams blast no craters. They still hurt. |

All three apply on top of the game's mob griefing switch: Mineclonia's gamerule
(`/gamerule mobs_griefing false`), VoxeLibre's `mobs_griefing` setting. With that off,
nothing is destroyed. Protected areas are never touched.

## Requirements

- Luanti 5.10 or newer (the models are glTF).
- Mineclonia or VoxeLibre.

## Known limitations

See [ROADMAP.md](ROADMAP.md).

## License

[MIT](LICENSE), for the code and the media. The sounds are the games' own, used by name.
