#!/bin/sh
# The Apple app's test fixtures: the mock hub's scenes (test/apple_fixtures.bend)
# as mobile/ios/BackplaneTests/Fixtures/<scene>.json.
#   scripts/apple-fixtures.sh          write them
#   scripts/apple-fixtures.sh --check  fail when they differ from what the
#                                      Bend side makes now (scripts/test.sh)
set -eu
cd "$(dirname "$0")/.."
dir=mobile/ios/BackplaneTests/Fixtures
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bend test/apple_fixtures.bend > "$tmp/raw" 2>&1 || { cat "$tmp/raw"; exit 1; }
# (bend's own notice of a newer release is not the program's output)
grep -v 'is available: run bend update' "$tmp/raw" > "$tmp/out" || true
# every line is "<scene>\t<json>"; anything else is bend reporting an error
if grep -qv "$(printf '^[a-z-]*\t{')" "$tmp/out"; then
  grep -v "$(printf '^[a-z-]*\t{')" "$tmp/out"
  exit 1
fi
mkdir -p "$tmp/new"
while IFS="$(printf '\t')" read -r name json; do
  printf '%s\n' "$json" | python3 -c 'import json, sys; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))' > "$tmp/new/$name.json"
done < "$tmp/out"
if [ "${1:-}" = --check ]; then
  diff -r "$dir" "$tmp/new" || { echo "the Apple test fixtures are out of date: run scripts/apple-fixtures.sh"; exit 1; }
  echo "apple fixtures: up to date"
else
  rm -rf "$dir"
  mkdir -p "$dir"
  cp "$tmp/new/"*.json "$dir/"
  echo "wrote $(ls "$dir" | wc -l | tr -d ' ') fixtures to $dir"
fi
