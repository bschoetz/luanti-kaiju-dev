# Roadmap and known limitations

Open points, gathered from the developer documentation in
[luanti-kaiju-dev](https://github.com/bschoetz/luanti-kaiju-dev). Nothing here is
scheduled; contributions are welcome there.

## Planned

- Release on ContentDB.

## VoxeLibre

The kaiju run on VoxeLibre through a compatibility layer, with these degradations
compared with Mineclonia:

- **A simpler pathfinder** (`kaiju_core/vl_path.lua`, same rules as Mineclonia's for a
  wide body). Remaining limits: it sees 24 nodes around the kaiju and gets 4 ms per search
  (about 100-150 cells), so far targets are reached in stretches, a wall longer than about
  40 nodes is bulldozed instead of walked around, and a way out of a large enclosed area
  can be missed. Caves and overhangs lower than the body count as walls. As on Mineclonia,
  the stuck detection fires during a detour of more than 3 s that does not bring the kaiju
  closer to its target, and he then bulldozes straight at it for 6 s.
- **Simpler walking physics** (fixed walking speed, braking in water, pushing out of other
  mobs; ice, cobwebs and water currents don't slow or move the kaiju).
- **Environmental damage** is Mineclonia's (lava, fire, magma, suffocation), except that
  rain doesn't keep a kaiju from catching fire and powder snow doesn't freeze it.
- **Griefing** follows VoxeLibre's `mobs_griefing` setting for all kaiju (Mineclonia: a
  gamerule per mob); the random block drops follow `mcl_doTileDrops`.
- **Sounds:** no ghast hurt sound, Ghidorah uses the parrot's.
- **Armour** rounds each hit to whole HP: one of Ghidorah's heads does nothing to a
  player in iron armour, two do nothing through diamond; all three always hurt.

## Gojira

- A flyer more than 48 nodes away above him is out of reach of his bite and his breath:
  he walks below it and waits.
- The server doesn't know his animated pose: flames start at a fixed mouth position, the
  hit boxes don't follow the animation, and his head and tail are not pointable.
- Mob projectiles and Ghidorah's beams ignore his hit boxes and must pass within 5 nodes
  of his feet.
- Smashing costs server time (about 4 ms per tick, more in dense terrain); several Gojiras
  multiply it.
- The tail sweep misses blocks during very slow or very fast turns.
- His big body can't pass 1-wide gaps; with griefing off he gets stuck in forests and
  villages.
- The die pose sinks about 0.7 nodes into the ground.

## Mothra

- **Altitude cap:** she flies at most 60 nodes above the ground under her target. A
  Ghidorah flying more than about 53 nodes up is out of her gust, above 60 out of her
  powder. Over drops deeper than 64 nodes the cap misjudges the ground.
- Terrain clearance looks only under her centre: her 26-node wings can clip a tower or a
  cave wall beside her path, and under the open sky a 1-2 node spike can be missed.
- Under a roof (caves, the Nether) she stays below it, but looks for no way around rock:
  she flies as far as there is room and holds there, so a target behind it stays out of
  reach.
- She never lands. Death drops above 105 nodes vanish.
- Poison does nothing to undead and spiders.

## King Ghidorah

- **Side-head reach:** the side heads only aim within a 60° cone and 40 nodes, and on
  their own only at players and kaiju other than the main target. At the enemy he is
  biting they fire a weaker volley every 12 s, and only if the beams would hit: a kaiju
  yes, a player right below the heads no. A side volley can fire nothing when its target
  leaves the cone.
- **Smashing in the air** leaves natural terrain alone, and a block a player placed is
  not told apart from the same block in the ground: he flies over a hut of dirt, stone or
  plain sandstone instead of through it. A tower he flies through loses the slice his
  body passes; what is above it stays in the air. His wander height still counts tree
  tops and roofs as ground.
- A smash pass in the air covers a larger box than on foot (2-5 ms; a whole tree canopy
  going at once can take 0.2 s on Mineclonia).
- Under a roof lower than 21 nodes he stays on foot. A flight that a wall or a low roof
  blocks ends in a landing, and he walks for 20 s before he tries again; he looks for no
  way around. If he finds no level, dry ground to land on (9 spots are tried), he comes
  down where he is.
- His altitude when chasing a flyer is capped at 40 nodes above the ground.
- Head positions come from fixed poses: beams and hit boxes can be a node off the drawn
  heads. A hit on a severed head's stump damages the body.
- A beam stops at the first player or kaiju on its line, which may not be his target.
- Network cost: bone overrides and four hit-box objects per Ghidorah.

## Cthulhu

- At sea he swims in straight lines (no pathfinder); an island of unbreakable or protected
  blocks stops him. At steep shores he climbs out by lifting over the edge or digs a ramp.
- Land mobs include animals: a cow on the beach wakes him. "Under the open sky" is a light
  test, so a mob just inside a cave mouth still counts.
- He ignores flyers as intruders; if they hurt him he gives up after 12 s out of reach.
- A grab drags the victim through nodes on the way to his claws; in shallow water the
  victim hangs in the air and doesn't drown.
- Darkness from his aura is strong in Mineclonia (the screen is black within 12 nodes);
  nausea needs shaders.
- On a flat shore his home can be 40-48 nodes out, so the beach behind the egg spot is
  outside his territory. Use the egg at the waterline.
- Players can still hit a fleeing Cthulhu under water; only mobs lose him.
- Balance is measured only in short fights; long fights in his own water are untested.
- The swim animation slides; hit boxes use the stand pose.

## All kaiju

- Transient state (a half-finished breath or volley, cooldowns) is saved with the world and
  resumes after a reload.
- Line of sight is needed to acquire a target.
- Terrain checks are only tested on flat worlds and one ocean beach.
