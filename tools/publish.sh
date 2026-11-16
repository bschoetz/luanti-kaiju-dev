#!/bin/sh
# Builds the two public repositories under gh/ from the committed state of this workspace:
#   gh/luanti-kaiju/      play-only: the modpack (runtime files), README, ROADMAP, LICENSE,
#                         .cdb.json, screenshots/
#   gh/luanti-kaiju-dev/  development: kaiju/, tools/, tests/ (without tests/out), README, LICENSE
# Each is a git repository of its own, created on the first run. Nothing is pushed and no
# remote is added.
#
#   tools/publish.sh [--no-shots] [--commit]
#
# --no-shots  keep the screenshots in gh/luanti-kaiju/screenshots/ as they are.
#             Otherwise they are shot with tests/run.sh readme_shots (Luanti, Xvfb, ImageMagick,
#             the game in $LUANTI_GAME_PATH, default vendor/) when kaiju/, tests/readme_shots,
#             tests/lib or tests/run.sh changed since the last shots (gh/.shots-stamp), so a
#             second run without a dev change leaves everything as it is.
# --commit    commit in each target: "build from dev@<short sha>".
#
# Sources: git archive HEAD (never the working tree); the run refuses to start when kaiju/,
# tools/ or tests/ have uncommitted or untracked changes. Templates: tools/publish/.
set -eu

REPO=$(cd "$(dirname "$0")/.." && pwd)
GH=$REPO/gh
PLAY=$GH/luanti-kaiju
DEV=$GH/luanti-kaiju-dev
SHOTS=1
COMMIT=0
for a in "$@"; do
	case $a in
	--no-shots) SHOTS=0 ;;
	--commit) COMMIT=1 ;;
	*) echo "usage: $0 [--no-shots] [--commit]" >&2; exit 2 ;;
	esac
done

cd "$REPO"
if [ -n "$(git status --porcelain -- kaiju tools tests)" ]; then
	git status --short -- kaiju tools tests >&2
	echo "publish: kaiju/, tools/ or tests/ have uncommitted changes; commit them first" >&2
	exit 1
fi
SHA=$(git rev-parse --short HEAD)
echo "publish: dev workspace $REPO at $SHA"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/src"
git archive HEAD | tar -x -C "$WORK/src"
# Never published, even if they get tracked one day.
( cd "$WORK/src" && rm -rf vendor tests/out gh .claude .vscode .idea && \
	find . \( -name '.claude' -o -iname '*memory*' -o -name '*~' -o -name '*.swp' -o -name '.*.swp' \
		-o -name '*.orig' -o -name '*.rej' -o -name '.DS_Store' -o -iname 'scratch*' \) -exec rm -rf {} + )

# Creates the repository, or empties it except .git (and the paths given after it).
prepare() {
	dir=$1; shift
	echo "==> $dir"
	if [ ! -d "$dir/.git" ]; then
		mkdir -p "$dir"
		git -C "$dir" init -q -b main
		echo "    new repository"
	fi
	keep="! -name .git"
	for k in "$@"; do keep="$keep ! -name $k"; done
	# shellcheck disable=SC2086
	find "$dir" -mindepth 1 -maxdepth 1 $keep -exec rm -rf {} +
}

# --- luanti-kaiju (play) --------------------------------------------------------------
prepare "$PLAY" screenshots
S=$WORK/src
cp "$S/kaiju/modpack.conf" "$S/kaiju/settingtypes.txt" "$PLAY/"
for mod in "$S"/kaiju/*/; do
	m=$(basename "$mod")
	mkdir -p "$PLAY/$m"
	# runtime files only: Lua, mod.conf, media; the developer READMEs stay in the dev repo
	( cd "$mod" && find . -type f \( -name '*.lua' -o -name 'mod.conf' -o -name 'settingtypes.txt' \
		-o -path './models/*' -o -path './textures/*' -o -path './sounds/*' -o -path './locale/*' \) \
		-exec cp --parents {} "$PLAY/$m/" \; )
done
cp "$S/tools/publish/README.md" "$S/tools/publish/ROADMAP.md" "$S/tools/publish/.cdb.json" "$S/LICENSE" "$PLAY/"

# --- screenshots ----------------------------------------------------------------------
NAMES="1-hero 2-gojira 3-mothra 4-ghidorah 5-cthulhu"
STAMP=$(git rev-parse HEAD:kaiju HEAD:tests/readme_shots HEAD:tests/lib HEAD:tests/run.sh | tr '\n' ' ')
have_all=1
for n in $NAMES; do [ -f "$PLAY/screenshots/$n.png" ] || have_all=0; done
if [ $SHOTS = 0 ]; then
	echo "    screenshots: kept (--no-shots)"
elif [ $have_all = 1 ] && [ "$(cat "$GH/.shots-stamp" 2>/dev/null)" = "$STAMP" ]; then
	echo "    screenshots: up to date with kaiju/ and tests/readme_shots"
else
	echo "    screenshots: shooting tests/readme_shots (about 2 minutes) ..."
	LUANTI_GAME_PATH=${LUANTI_GAME_PATH:-$REPO/vendor} "$S/tests/run.sh" readme_shots 40 > "$WORK/shots.log" 2>&1 \
		|| { cat "$WORK/shots.log" >&2; echo "publish: readme_shots failed" >&2; exit 1; }
	RUN=$(cd "$S/tests/out/readme_shots" && pwd -P)
	# scene start times (s) from the log; a frame belongs to scene n if it was written from 2 s
	# after its start until 1 s before the next one; the last such frame is taken
	grep 'SCENE [0-9]' "$RUN/client.log" | sed -E 's/^([0-9-]+ [0-9:]+): .*SCENE ([0-9]+).*/\1|\2/' |
		while IFS='|' read -r t n; do echo "$(date -d "$t" +%s) $n"; done > "$WORK/scenes"
	for f in "$RUN"/s_*.png; do echo "$(stat -c %Y "$f") $f"; done > "$WORK/frames"
	mkdir -p "$WORK/shots"
	IM=convert; command -v magick >/dev/null && IM=magick
	i=0
	for n in $NAMES; do
		i=$((i + 1))
		start=$(awk -v i=$i '$2 == i {print $1}' "$WORK/scenes")
		next=$(awk -v i=$((i + 1)) '$2 == i {print $1}' "$WORK/scenes")
		[ -n "$start" ] || { echo "publish: scene $i was never shot (see $RUN)" >&2; exit 1; }
		[ -n "$next" ] || next=$((start + 6))
		f=$(awk -v a=$((start + 2)) -v b=$((next - 1)) '$1 >= a && $1 <= b {f = $2} END {print f}' "$WORK/frames")
		[ -n "$f" ] || { echo "publish: no frame for scene $i (see $RUN)" >&2; exit 1; }
		$IM "$f" -resize '1280x>' -strip "$WORK/shots/$n.png"
		if command -v pngquant >/dev/null; then
			pngquant --force --quality 80-98 --speed 1 --strip --output "$WORK/shots/$n.png" "$WORK/shots/$n.png"
		fi
		echo "    $n.png <- $(basename "$f")"
	done
	rm -rf "$PLAY/screenshots"
	mv "$WORK/shots" "$PLAY/screenshots"
	echo "$STAMP" > "$GH/.shots-stamp"
fi

# --- luanti-kaiju-dev -----------------------------------------------------------------
prepare "$DEV"
cp -r "$S/kaiju" "$S/tools" "$S/tests" "$S/README.md" "$S/LICENSE" "$S/.gitignore" "$DEV/"
rm -rf "$DEV/tests/out"

# --- privacy checks -------------------------------------------------------------------
fail=0
EMAIL=$(git config user.email || true)
for dir in "$PLAY" "$DEV"; do
	if grep -rInE --exclude-dir=.git '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$dir"; then
		echo "publish: e-mail address in $dir" >&2; fail=1
	fi
	if grep -rInE --exclude-dir=.git '(^|[^A-Za-z0-9_$}.-])/home/[A-Za-z0-9_]' "$dir"; then
		echo "publish: absolute /home/ path in $dir" >&2; fail=1
	fi
	# binary files too (models, textures, screenshots)
	for s in "$EMAIL" "$HOME"; do
		if [ -n "$s" ] && grep -rlaF --exclude-dir=.git "$s" "$dir"; then
			echo "publish: '$s' found in $dir" >&2; fail=1
		fi
	done
	if find "$dir" -path "$dir/.git" -prune -o \( -name '.claude' -o -iname '*memory*' -o -name out -path '*/tests/out' \) -print | grep .; then
		echo "publish: private files in $dir" >&2; fail=1
	fi
done
[ $fail = 0 ] || exit 1
echo "    privacy checks passed"

# --- status / commit ------------------------------------------------------------------
for dir in "$PLAY" "$DEV"; do
	echo "==> git status in $dir"
	git -C "$dir" add -A
	git -C "$dir" status --short
	if [ -z "$(git -C "$dir" status --porcelain)" ]; then
		echo "    no changes"
	elif [ $COMMIT = 1 ]; then
		git -C "$dir" commit -q -m "build from dev@$SHA"
		echo "    committed $(git -C "$dir" rev-parse --short HEAD): build from dev@$SHA"
	fi
done
