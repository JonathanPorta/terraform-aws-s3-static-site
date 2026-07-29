#!/usr/bin/env bash
# assert-actions-pinned.sh — every third-party `uses:` in .github/ must name a
# full 40-character commit SHA.
#
# WHY A SCRIPT INSTEAD OF A ONE-LINE grep
#
# The previous gate was a denylist:
#
#   grep -RnE 'uses:[[:space:]]+[^./].*@(v[0-9]|main|master|latest)([[:space:]]|$)'
#
# It was green while two floating refs sat in the release workflow, because a
# denylist only catches the float spellings someone thought to enumerate:
#
#   * `uses: 'WyriHaximus/...@v1'` — the trailing quote sits where the pattern
#     demanded whitespace-or-end-of-line, so the match failed.
#   * `@v1.0.0` — `v[0-9]` matched `v1`, then `.0.0` was neither whitespace nor
#     end of line, so again no match.
#   * `@my-branch`, `@abc1234` — never enumerated at all.
#
# So it is an allowlist here instead. Anything that is not provably immutable is
# a violation, and a spelling nobody anticipated fails closed rather than open.
# That inverts the failure mode: the gate can now be wrong about what a pin
# looks like and still refuse to pass an unpinned ref.
set -uo pipefail

pass=0; fail=0
ok() { echo "  ✓ $1"; pass=$((pass + 1)); }
no() { echo "  ✗ $1"; fail=$((fail + 1)); }

# ── normalisation ────────────────────────────────────────────────────────────
# Reduce the raw YAML scalar following `uses:` to the bare ref it denotes.
# GitHub accepts the value bare, single-quoted or double-quoted, with an
# optional trailing comment — all four spellings must reduce to the same thing
# before the ref is examined. Skipping this step is what hid the two quoted
# floats from the old regex.
normalize_ref() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}" # ltrim
  case "$v" in
    \'*) v="${v#\'}"; v="${v%%\'*}" ;; # single-quoted: stop at the closing quote
    \"*) v="${v#\"}"; v="${v%%\"*}" ;; # double-quoted: ditto
    *) v="${v%%[[:space:]]*}" ;;       # bare: stop at whitespace, dropping any comment
  esac
  printf '%s' "$v"
}

# ── the rule ─────────────────────────────────────────────────────────────────
# Immutable, and nothing else:
#
#   * `./…` — first-party, lives in this tree, reviewed with the diff that
#     changes it. There is no upstream to retag.
#   * `docker://…@sha256:<64 hex>` — a registry *tag* stays mutable no matter
#     how much it looks like a version, so only a content digest counts.
#   * `owner/repo@<40 lowercase hex>` — a commit SHA. Anything shorter is a
#     prefix, which is not the same guarantee; anything longer or non-hex is
#     not a SHA at all.
ref_is_pinned() {
  local ref="$1" at="${1##*@}"
  case "$ref" in
    ./*) return 0 ;;
    docker://*)
      [[ "$at" =~ ^sha256:[0-9a-f]{64}$ ]] && return 0
      return 1
      ;;
  esac
  [[ "$ref" == *@* ]] || return 1 # no ref at all == whatever the default branch holds today
  [[ "$at" =~ ^[0-9a-f]{40}$ ]]
}

# ── self-test ────────────────────────────────────────────────────────────────
# A gate that silently stops matching is worse than no gate: it reports the
# safety it is no longer providing. These cases are the regression for the
# specific blind spots the denylist had, so it cannot quietly regain them.
expect() { # expect <pinned|floating> <raw scalar as written after `uses:`>
  local want="$1" raw="$2" ref got
  ref="$(normalize_ref "$raw")"
  if ref_is_pinned "$ref"; then got=pinned; else got=floating; fi
  if [ "$got" = "$want" ]; then
    ok "$want ← ${raw}"
  else
    no "expected $want, got $got ← ${raw}   (normalised to '${ref}')"
  fi
}

echo "── the audit itself (self-test) ──"

# Accepted: a full commit SHA, however it is quoted or commented.
expect pinned ' actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803'
expect pinned ' actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803  # v6'
expect pinned " 'actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803'"
expect pinned ' "actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803"  # v6'
expect pinned ' owner/repo/.github/workflows/reusable.yml@d23441a48e516b6c34aea4fa41551a30e30af803'

# Accepted: first-party, and a digest-pinned container.
expect pinned ' ./.github/actions/slack-notify'
expect pinned ' docker://ghcr.io/o/i@sha256:0000000000000000000000000000000000000000000000000000000000000000'

# Rejected: quoted floats — the pair the old regex could not see.
expect floating " 'WyriHaximus/github-action-get-previous-tag@v1'"
expect floating ' "WyriHaximus/github-action-next-semvers@v1"'

# Rejected: dotted tags — `v[0-9]` matched, the anchor then failed.
expect floating ' terraform-docs/gh-actions@v1.0.0'
expect floating " 'terraform-docs/gh-actions@v1.0.0'  # comment"

# Rejected: branch refs, including ones no denylist would have listed.
expect floating ' some/action@main'
expect floating ' some/action@master'
expect floating ' some/action@latest'
expect floating ' some/action@my-feature-branch'

# Rejected: SHA prefixes. A prefix is not a pin.
expect floating ' some/action@d23441a'
expect floating ' some/action@d23441a48e51'

# Rejected: things shaped like a SHA but not one.
expect floating ' some/action@D23441A48E516B6C34AEA4FA41551A30E30AF803' # uppercase
expect floating ' some/action@z23441a48e516b6c34aea4fa41551a30e30af803' # non-hex
expect floating ' some/action@d23441a48e516b6c34aea4fa41551a30e30af8030' # 41 chars

# Rejected: no ref at all, and a container on a mutable tag.
expect floating ' some/action'
expect floating ' docker://quay.io/terraform-docs/gh-actions:1.0.0'

# ── the actual audit ─────────────────────────────────────────────────────────
echo "── every uses: in .github/ ──"
found=0
while IFS=: read -r file lineno rest; do
  found=$((found + 1))
  ref="$(normalize_ref "${rest#*uses:}")"
  if ref_is_pinned "$ref"; then
    ok "$file:$lineno  $ref"
  else
    no "$file:$lineno  $ref  ← not immutable"
  fi
done < <(grep -RnE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]' .github/ \
  --include='*.yml' --include='*.yaml')

# A scan that matched nothing looks identical to a scan that found no problems.
if [ "$found" -eq 0 ]; then
  no "no uses: lines found at all — the scan is broken, not the workflows clean"
else
  ok "scanned $found uses: refs"
fi

echo
total=$((pass + fail))
if [ "$fail" -eq 0 ]; then
  echo "actions-pinned: PASS ($total checks)"
  exit 0
fi
echo "actions-pinned: FAIL ($fail of $total)"
echo "pin each ref above to a full 40-character commit SHA, keeping the version as a trailing comment:"
echo "  uses: owner/repo@<40-hex>  # v1.2.3"
exit 1
