#!/usr/bin/env bash
# next-version.sh — print the version tag a given semver bump would cut.
#
#   next-version.sh minor            # against this repo's tags
#   next-version.sh minor 1.4.0      # against an explicit previous tag
#
# Extracted from the release workflow so the arithmetic that names a release can
# be run and tested here, instead of being discovered to be wrong by a bad tag on
# master. `--self-test` runs the table at the bottom.
#
# Tags in this repo are bare `MAJOR.MINOR.PATCH` with no `v` prefix (1.4.0), and
# that is what this prints.
set -euo pipefail

next_version() { # next_version <major|minor|patch> <previous>
  local bump="$1" prev="$2" ma mi pa
  if [[ ! "$prev" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "previous tag '$prev' is not MAJOR.MINOR.PATCH" >&2
    return 1
  fi
  ma="${BASH_REMATCH[1]}"; mi="${BASH_REMATCH[2]}"; pa="${BASH_REMATCH[3]}"
  case "$bump" in
    major) ma=$((ma + 1)); mi=0; pa=0 ;;
    minor) mi=$((mi + 1)); pa=0 ;;
    patch) pa=$((pa + 1)) ;;
    *) echo "unknown bump '$bump' (want major|minor|patch)" >&2; return 1 ;;
  esac
  printf '%s.%s.%s\n' "$ma" "$mi" "$pa"
}

# Highest release tag currently on the repo. Only bare MAJOR.MINOR.PATCH counts,
# so a stray `v2-beta` or a moving pointer tag cannot become the base of the
# arithmetic. No tags at all means the first release is computed from 0.0.0.
previous_tag() {
  git tag --sort=-v:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -1
}

if [ "${1:-}" = "--self-test" ]; then
  p=0; f=0
  t() { # t <expected> <bump> <prev>
    local got
    got="$(next_version "$2" "$3")"
    if [ "$got" = "$1" ]; then echo "  ✓ $3 --$2--> $got"; p=$((p + 1));
    else echo "  ✗ $3 --$2--> $got, expected $1"; f=$((f + 1)); fi
  }
  echo "── version arithmetic ──"
  t 2.0.0 major 1.4.0
  t 1.5.0 minor 1.4.0   # the release this PR requests
  t 1.4.1 patch 1.4.0
  t 1.0.0 major 0.0.0
  t 0.1.0 minor 0.0.0
  t 0.0.1 patch 0.0.0
  # The components are integers, not decimals: 1.9.0 minor-bumps to 1.10.0, and
  # 1.4.9 patch-bumps to 1.4.10. Neither rolls over into the component above it.
  t 1.10.0 minor 1.9.0
  t 1.4.10 patch 1.4.9
  t 10.0.0 major 9.9.9

  echo "── malformed input is refused, not guessed at ──"
  for bad in "v1.4.0" "1.4" "1.4.0-rc1" ""; do
    if next_version minor "$bad" > /dev/null 2>&1; then
      echo "  ✗ accepted malformed previous tag '$bad'"; f=$((f + 1))
    else
      echo "  ✓ refused '$bad'"; p=$((p + 1))
    fi
  done
  if next_version sideways 1.4.0 > /dev/null 2>&1; then
    echo "  ✗ accepted unknown bump"; f=$((f + 1))
  else
    echo "  ✓ refused unknown bump"; p=$((p + 1))
  fi

  echo
  [ "$f" -eq 0 ] && { echo "next-version: PASS ($((p + f)) checks)"; exit 0; }
  echo "next-version: FAIL ($f of $((p + f)))"; exit 1
fi

bump="${1:?usage: next-version.sh <major|minor|patch> [previous-tag]}"
prev="${2:-$(previous_tag)}"
prev="${prev:-0.0.0}"
next_version "$bump" "$prev"
