#!/bin/sh
# Upgrade check: a world made with the four separate mod folders (the layout before the
# `kaiju` modpack) must keep its kaiju and spawn eggs after switching to the modpack.
#   tests/compat.sh [old-mods-dir]
# The mods are installed like a user does it, in ~/.minetest/mods of an isolated HOME, and
# enabled in world.mt with the paths the "Select Mods" dialog writes:
#   1. old layout: mods/{kaiju_core,gojira,mothra,ghidorah}, taken from [old-mods-dir] (e.g.
#      a checkout of an older commit; default: the current mods, linked flat). Spawns the
#      three kaiju, puts their eggs in the inventory, saves.
#   2. new layout (mods/kaiju/...), world.mt updated to the modpack paths: the kaiju must be
#      back and active, the eggs still known items.
#   3. for information: world.mt put back to the old paths, i.e. the upgrade step a user can
#      forget. Luanti then starts the world without the kaiju mods (ERROR lines), and kaiju
#      in loaded areas are unknown entities that drift away or sink.
# The game is chosen as in run.sh (LUANTI_GAME, LUANTI_GAME_PATH).
# Output: tests/out/compat-<time>-<pid>/ (stepN.log, test.log). Exit 1 unless step 2 finds
# all three kaiju stepping and all three eggs.
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
OLD=${1:-$REPO/kaiju}
MODS="kaiju_core gojira mothra ghidorah"
OUT=$REPO/tests/out/compat-$(date +%Y%m%d-%H%M%S)-$$
export HOME=$OUT/home XDG_DATA_HOME=$OUT/home/.local/share XDG_CACHE_HOME=$OUT/home/.cache XDG_CONFIG_HOME=$OUT/home/.config
export LUANTI_GAME_PATH=${LUANTI_GAME_PATH:-$REPO/vendor}
GAME=${LUANTI_GAME:-mineclonia} # game id: a folder in $LUANTI_GAME_PATH (mineclone2 is VoxeLibre)
unset WAYLAND_DISPLAY
USERMODS=$HOME/.minetest/mods
mkdir -p "$USERMODS" "$OUT/world/worldmods"
ln -s "$REPO/tests/kaiju_compat" "$OUT/world/worldmods/kaiju_compat"
{
	printf 'enable_sound = false\nmute_sound = true\nscreen_w = 960\nscreen_h = 600\n'
	printf 'name = tester\nenable_damage = true\nmg_name = flat\nfixed_map_seed = 1\n'
	cat "$REPO/tests/kaiju_compat/test.conf"
} > "$OUT/test.conf"

world_mt() { # $1: path prefix of the mods below mods/
	printf 'gameid = %s\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\n' "$GAME" > "$OUT/world/world.mt"
	for m in $MODS; do echo "load_mod_$m = mods/$1$m" >> "$OUT/world/world.mt"; done
}
run() { # $1: step number
	timeout 120 xvfb-run -a -s "-screen 0 960x600x24" luanti --config "$OUT/test.conf" --world "$OUT/world" \
		--go --port $((30100 + $$ % 800)) --name tester --logfile "$OUT/step$1.log" >/dev/null 2>&1 || true
	[ -s "$OUT/step$1.log" ] || { echo "FAILED: luanti wrote no $OUT/step$1.log" >&2; exit 1; }
	{ grep '\[test\]' "$OUT/step$1.log" | sed "s/.*\[test\] /step $1: /"
		grep -E 'ERROR\[' "$OUT/step$1.log" | grep -v poplar | sed "s/^[^:]*:[^:]*:[^:]*: /step $1: /" || true
	} | tee -a "$OUT/test.log"
}

echo "step 1: old layout ($OLD)"
for m in $MODS; do ln -s "$OLD/$m" "$USERMODS/$m"; done
world_mt ""
run 1
echo "step 2: modpack installed and enabled in world.mt"
for m in $MODS; do rm "$USERMODS/$m"; done
ln -s "$REPO/kaiju" "$USERMODS/kaiju"
world_mt "kaiju/"
run 2
echo "step 3 (for information): modpack installed, world.mt still has the old paths"
world_mt ""
run 3

if grep -q 'step 2: loaded: gojira:gojira=[0-9]*(hp [^,]*, steps [1-9][0-9]*, at [^ ]*) mothra:mothra=[0-9]*(hp [^,]*, steps [1-9][0-9]*, at [^ ]*) ghidorah:ghidorah=[0-9]*(hp [^,]*, steps [1-9][0-9]*, at [^ ]*) | eggs: gojira:gojira=true mothra:mothra=true ghidorah:ghidorah=true' "$OUT/test.log"; then
	echo "ok: $OUT"
else
	echo "FAILED: the kaiju did not survive the upgrade, see $OUT" >&2
	exit 1
fi
