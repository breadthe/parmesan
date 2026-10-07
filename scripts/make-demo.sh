#!/bin/bash
# Builds a demo folder tree in ./demo (gitignored) that shows every state Parmesan draws, for
# screenshots, manual testing and as a reference for test fixtures. Re-running it deletes and rebuilds
# ./demo from scratch. Scan it with: open Parmesan, then drop the demo folder on the window.
#
#   Movies, Photos, Music     big files with real allocated data: a clear "biggest chunk" plus a long tail
#   Documents, Downloads      every By Kind category (.pdf, .zip, .dmg, .pkg, …), old and new dates
#   Developer/storefront      a node_modules-like tree nested 8+ levels, .git, DerivedData, Swift sources
#   Applications/Demo.app     a package (drawn as a folder with a badge, can be drilled into)
#   Cache                     thousands of tiny files, grouped into "N smaller items" on the chart
#   Deep                      a file 10 levels down
#   Links                     a hard link pair (counted once) and a symlink to Movies (not followed)
#   Locked                    chmod 000: shown as Restricted and left out of the totals
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO="$ROOT/demo"
MARKER=".parmesan-demo"

if [ -e "$DEMO" ] && [ ! -e "$DEMO/$MARKER" ]; then
  echo "$DEMO exists but wasn't made by this script; not touching it." >&2
  exit 1
fi
# The Locked folder from a previous run has no permissions; give them back so it can be deleted.
[ -d "$DEMO" ] && chmod -R u+rwx "$DEMO" 2>/dev/null || true
rm -rf "${DEMO:?}"
mkdir -p "$DEMO"
touch "$DEMO/$MARKER"
cd "$DEMO"

# blob <path> <size>: a file with real allocated blocks (mkfile without -n; sparse files allocate almost nothing).
blob() {
  mkdir -p "$(dirname "$1")"
  mkfile "$2" "$1"
}

# text <path> <line>: a small text file.
text() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
}

# age <YYYYMMDDhhmm> <path>...: sets modification dates, for By Age.
age() {
  local when=$1
  shift
  touch -t "$when" "$@"
}

echo "Writing demo tree to $DEMO …"

# ---------------------------------------------------------------- media: the biggest chunks
blob Movies/Holiday\ 2019.mov 110m
blob Movies/Trailer.mp4 38m
blob Movies/Clips/interview-raw.mov 24m
blob Movies/Clips/b-roll.m4v 9m
age 201908141030 Movies/Holiday\ 2019.mov
age 202310021200 Movies/Clips/interview-raw.mov

for i in $(seq -w 1 24); do blob "Photos/2018/IMG_18$i.jpg" 2200k; done
for i in $(seq -w 1 16); do blob "Photos/2025/IMG_25$i.heic" 1400k; done
for i in 1 2 3 4; do blob "Photos/RAW/DSC0000$i.dng" 9m; done
age 201806151200 Photos/2018/* Photos/2018
age 202104101200 Photos/RAW/*

for i in $(seq -w 1 10); do blob "Music/Album/Track $i.mp3" 4m; done
blob Music/Voice\ Memo.m4a 3m
age 202011201800 Music/Album/*

# ---------------------------------------------------------------- documents and downloads
for i in 1 2 3 4 5; do blob "Documents/Reports/Quarterly report Q$i.pdf" 2500k; done
blob Documents/Budget.xlsx 600k
blob Documents/Slides.pptx 4m
for i in $(seq 1 150); do text "Documents/Notes/note-$i.md" "Note $i"; done
age 202301091000 Documents/Reports/*
age 201702011000 Documents/Notes/note-1*.md

blob Downloads/Xcode_Installer.dmg 64m
blob Downloads/Photos-backup.zip 26m
blob Downloads/Driver.pkg 9m
blob Downloads/dataset.tar.gz 7m
age 202103031200 Downloads/Xcode_Installer.dmg

# ---------------------------------------------------------------- developer: deep trees and dev artifacts
P=Developer/storefront
for f in App Cart Checkout Product Search; do text "$P/Sources/$f.swift" "struct $f {}"; done
blob "$P/.git/objects/pack/pack-1.pack" 16m
for i in $(seq 1 40); do text "$P/.git/objects/$((10 + i))/obj$i" "blob $i"; done
blob "$P/DerivedData/Build/Products/Debug/Storefront.app/Contents/MacOS/Storefront" 14m
blob "$P/DerivedData/Index.noindex/DataStore/records.db" 11m
# node_modules: packages with nested node_modules, 8+ levels deep, many small files.
nm="$P/node_modules"
for pkg in react react-dom lodash typescript esbuild vite eslint chalk; do
  blob "$nm/$pkg/dist/index.js" 300k
  for i in $(seq 1 60); do text "$nm/$pkg/lib/file$i.js" "module.exports = $i"; done
  text "$nm/$pkg/package.json" "{\"name\": \"$pkg\"}"
done
deep="$nm/eslint/node_modules/@eslint/core/node_modules/ajv/node_modules/fast-deep-equal/node_modules/json-schema/lib"
for i in $(seq 1 20); do text "$deep/schema$i.json" "{}"; done
blob "$nm/esbuild/bin/esbuild" 9m

# ---------------------------------------------------------------- a package
A=Applications/Demo.app/Contents
blob "$A/MacOS/Demo" 12m
blob "$A/Frameworks/Engine.framework/Engine" 7m
for i in $(seq 1 30); do blob "$A/Resources/Assets/image$i.png" 120k; done
text "$A/Info.plist" "<plist/>"

# ---------------------------------------------------------------- thousands of tiny files
for d in $(seq -w 1 20); do
  mkdir -p "Cache/shard$d"
  for i in $(seq 1 100); do printf 'x' > "Cache/shard$d/entry$i.cache"; done
done

# ---------------------------------------------------------------- deep nesting
blob Deep/a/b/c/d/e/f/g/h/i/j/bottom.bin 5m

# ---------------------------------------------------------------- links
blob Links/original.bin 20m
ln Links/original.bin Links/hard-link.bin
ln -s ../Movies Links/movies-symlink

# ---------------------------------------------------------------- restricted
blob Locked/secret.bin 8m
chmod 000 Locked

# ---------------------------------------------------------------- expected total
# Allocated bytes of every file once per inode (hard links once, symlinks as themselves, Locked unreadable).
expected=$(find . -path ./Locked -prune -o \( -type f -o -type l \) -print0 2>/dev/null |
  xargs -0 stat -f '%i %b' | sort -u -k1,1 | awk '{ s += $2 * 512 } END { printf "%.0f", s }')
echo
echo "Done. Expected allocated total (Locked excluded): $expected bytes ($((expected / 1024)) KiB)"
echo "du -sk demo: $(du -sk "$DEMO" 2>/dev/null | cut -f1) KiB"
echo "Locked/ is chmod 000 on purpose; this script restores it before rebuilding."
