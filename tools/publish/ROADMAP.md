# Roadmap and known limitations

Open points, gathered from the developer documentation in
[luanti-kaiju-dev](https://github.com/bschoetz/luanti-kaiju-dev). Nothing here is
scheduled; contributions are welcome there.

## Planned

- Release on ContentDB.

## VoxeLibre

The kaiju run on VoxeLibre through a compatibility layer, with these degradations
compared with Mineclonia:

- **No pathfinder.** The kaiju walk in straight lines at their target or goal. With
  `kaiju_smash_blocks` off they get stuck sooner; they jump against a 2-node wall.
- **Simpler walking physics** (gravity, fixed walking speed, braking in water, pushing out
  of other mobs). Punches cause no knockback.
- **No environmental damage except burning:** lava, fire nodes, suffocation, drowning and
  fall damage don't hurt the kaiju.
- **No alerts:** Gojira's rule for mobs alerting others of their kind never fires.
- **Griefing** follows VoxeLibre's `mobs_griefing` setting for all kaiju (Mineclonia: a
  gamerule per mob); the random block drops follow `mcl_doTileDrops`.
- **Sounds:** no ghast hurt sound, Ghidorah uses the enderman's.
- Gojira out of deep water stays in the tunnel he dug instead of climbing out.
- Ghidorah's side heads beam on their own less often.

## Gojira

- **Dead zone:** between 7 nodes (bite reach) and 9 (shortest breath) he can neither bite
  nor breathe and walks closer. A target high above him (a flyer more than 32 nodes away,
  or above his head out of bite reach) is out of reach of both.
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
- **Ceilings are not handled.** Under a roof (caves, the Nether) her ground check hits the
  roof and she climbs into it. Keep her out of caves and the Nether.
- Terrain clearance looks only under her centre: her 26-node wings can clip a tower beside
  her path, and a 1-2 node spike can be missed.
- She never lands. Death drops above 105 nodes vanish.
- Poison does nothing to undead and spiders.

## King Ghidorah

- **Side-head reach:** the side heads only aim within a 60° cone and 40 nodes, only at
  players and kaiju, and only at an enemy other than the main target. With a single enemy
  in melee no head beams; a side volley can fire nothing when the target leaves the cone.
- **Ceilings for flyers:** flying he passes through terrain and can take off through a cave
  roof; he lands straight down, also on water or a roof, and without smashing can land
  inside a tree. No smashing in the air.
- His altitude when chasing a flyer is capped at 40 nodes above the ground.
- Head positions come from fixed poses: beams and hit boxes can be a node off the drawn
  heads. A hit on a severed head's stump damages the body.
- A beam hits the first enemy on its line, which may not be his target. Beam damage is
  high against unarmoured players.
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
