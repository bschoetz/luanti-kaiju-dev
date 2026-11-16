#!/bin/sh
# Runs one test scenario in a real, headless Luanti client (Xvfb) with Mineclonia or VoxeLibre.
#   tests/run.sh <scenario> [screenshots]
# <scenario> is a folder in tests/ (a worldmod that builds the scene, spawns the kaiju,
# logs "[test] ..." lines and shuts the server down when done). With [screenshots] = N,
# a screenshot is taken every second for N seconds (needs ImageMagick `import`).
# Output goes to tests/out/<scenario>-<time>-<pid>/ (tests/out/<scenario> links to the
# latest run): client.log, test.log ("[test]" lines), s_NN.png.
# Exit code 1 if the client never logged anything or an "ERROR[" line was logged.
#
# Needs: luanti (5.10+ client), xvfb-run, and the game $LUANTI_GAME (default: mineclonia)
# in $LUANTI_GAME_PATH (default: vendor/, i.e. vendor/mineclonia). VoxeLibre:
#   LUANTI_GAME=mineclone2 LUANTI_GAME_PATH=~/.minetest/games tests/run.sh <scenario>
set -eu

[ $# -ge 1 ] || { echo "usage: $0 <scenario> [screenshots]" >&2; ls "$(dirname "$0")" >&2; exit 2; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
NAME=$1
SHOTS=${2:-0}
GAME=${LUANTI_GAME:-mineclonia} # game id: a folder in $LUANTI_GAME_PATH (mineclone2 is VoxeLibre)
SRC=$REPO/tests/$NAME
[ -f "$SRC/init.lua" ] || { echo "no scenario tests/$NAME" >&2; exit 2; }

# Own folder per run (parallel runs of the same scenario must not delete each other's
# files); tests/out/<scenario> links to the latest one.
OUT=$REPO/tests/out/$NAME-$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$OUT/home" "$OUT/world/worldmods"
LATEST=$REPO/tests/out/$NAME
[ -L "$LATEST" ] || rm -rf "$LATEST" # output folder of an older run.sh
ln -sfn "$(basename "$OUT")" "$LATEST"
ln -s "$REPO/kaiju" "$OUT/world/worldmods/kaiju" # the modpack, as a user installs it
ln -s "$SRC" "$OUT/world/worldmods/$NAME"
ln -s "$REPO/tests/lib" "$OUT/world/worldmods/kaiju_test" # shared scenario helpers
printf 'gameid = %s\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\n' "$GAME" > "$OUT/world/world.mt"

# Common client/server settings, then the scenario's own (creative mode, fov, ...).
{
	printf 'enable_sound = false\nmute_sound = true\nscreen_w = 960\nscreen_h = 600\n'
	printf 'name = tester\nenable_damage = true\nmg_name = flat\nfixed_map_seed = 1\n'
	cat "$SRC/test.conf"
} > "$OUT/test.conf"

# Isolated home/config so the user's own Luanti settings and worlds are untouched.
export HOME=$OUT/home XDG_DATA_HOME=$OUT/home/.local/share XDG_CACHE_HOME=$OUT/home/.cache XDG_CONFIG_HOME=$OUT/home/.config
export LUANTI_GAME_PATH=${LUANTI_GAME_PATH:-$REPO/vendor}
unset WAYLAND_DISPLAY
# Each run listens on its own port so parallel runs don't collide.
PORT=$((30100 + $$ % 800))

cat > "$OUT/client.sh" <<EOF
#!/bin/sh
luanti --config "$OUT/test.conf" --world "$OUT/world" --go --port $PORT --name tester --logfile "$OUT/client.log" >/dev/null 2>&1 &
i=0
while [ \$i -lt $SHOTS ]; do sleep 1; i=\$((i+1)); import -window root "$OUT/s_\$(printf %02d \$i).png"; done
wait
EOF
chmod +x "$OUT/client.sh"

# The X screen matches the window (a scenario's test.conf may set screen_w / screen_h).
SCREEN="$(sed -n 's/^screen_w *= *//p' "$OUT/test.conf" | tail -n 1)x$(sed -n 's/^screen_h *= *//p' "$OUT/test.conf" | tail -n 1)x24"

echo "running $NAME (port $PORT) ..."
timeout 180 xvfb-run -a -s "-screen 0 $SCREEN" "$OUT/client.sh" || true
# A scenario with a file "restart" is started a second time on the same world (same log).
if [ -f "$SRC/restart" ]; then timeout 180 xvfb-run -a -s "-screen 0 $SCREEN" "$OUT/client.sh" || true; fi

[ -s "$OUT/client.log" ] || { echo "FAILED: luanti wrote no $OUT/client.log" >&2; exit 1; }
grep '\[test\]' "$OUT/client.log" | sed 's/.*\[test\] //' > "$OUT/test.log" || true
cat "$OUT/test.log"
# poplar: a missing texture in Mineclonia itself, unrelated to these mods
if grep -E 'ERROR\[' "$OUT/client.log" | grep -v poplar >&2; then
	echo "FAILED: errors in $OUT/client.log" >&2
	exit 1
fi
echo "ok: $OUT"
