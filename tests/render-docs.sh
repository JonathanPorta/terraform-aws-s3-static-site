#!/usr/bin/env bash
# render-docs.sh — regenerate the terraform-docs block inside README.md.
#
# Run this after changing variables.tf / outputs.tf and commit the result. CI
# runs the same script and fails if the committed README differs, so this is the
# one command that clears that check.
#
# WHY NOT terraform-docs/gh-actions
#
# The workflow used to call terraform-docs/gh-actions with `git-push: 'true'`.
# Two problems compounded:
#
#   1. Pinning that action to a commit SHA did not pin what ran. Its action.yml
#      is a thin wrapper that delegates to `docker://quay.io/terraform-docs/
#      gh-actions:1.0.0` — a registry *tag*, which is mutable. The reviewed
#      commit froze the wrapper and nothing else.
#   2. The step ran in a checkout with persisted credentials and pushed to the
#      PR branch. So repointing one Quay tag bought an attacker code execution
#      *and* commit access to the branch under review.
#
# Fetching a release archive and checking it against a digest recorded in this
# file closes (1): the bytes are fixed here, in the diff, not by an upstream
# tag. Making CI *verify* rather than *push* closes (2) — the job needs no write
# permission at all, so there is nothing left to steal.
set -euo pipefail

VERSION="v0.24.0"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

# From the signed release manifest:
# https://github.com/terraform-docs/terraform-docs/releases/download/v0.24.0/terraform-docs-v0.24.0.sha256sum
# Bumping VERSION means replacing these, and the mismatch is a hard failure
# rather than a silent upgrade.
sha_for() {
  case "$1" in
    linux-amd64) echo 9005daf969de0b50134493a2c00078b49f5f5b39d021cda7c89bf4d4f3d776d3 ;;
    linux-arm64) echo d12bd7b73c1fc9c64efc79f8157dd713dabd559f1ecf3cfc0f42e32279a155fd ;;
    darwin-amd64) echo 3c3f7f18f908457fd1209cbe341418f7f6bae78c08126cfbe8de0d1b06aa8781 ;;
    darwin-arm64) echo f6b114f4b032f3f9202ab6c23bfd28c3c8e68aeeb8a8f12fc118bf2073081d71 ;;
    *) return 1 ;;
  esac
}

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) echo "unsupported OS $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
esac
platform="$os-$arch"
want="$(sha_for "$platform")" || { echo "no recorded checksum for $platform" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tarball="terraform-docs-$VERSION-$platform.tar.gz"
echo "· fetching $tarball"
curl -fsSL -o "$tmp/$tarball" \
  "https://github.com/terraform-docs/terraform-docs/releases/download/$VERSION/$tarball"

# Verify BEFORE unpacking: an archive that fails the digest check must never be
# written to disk as an executable, let alone run.
got="$(shasum -a 256 "$tmp/$tarball" 2>/dev/null | cut -d' ' -f1 || sha256sum "$tmp/$tarball" | cut -d' ' -f1)"
if [ "$got" != "$want" ]; then
  echo "checksum mismatch for $tarball" >&2
  echo "  expected $want" >&2
  echo "  actual   $got" >&2
  exit 1
fi
echo "· sha256 ok"

tar -xzf "$tmp/$tarball" -C "$tmp" terraform-docs
chmod +x "$tmp/terraform-docs"

# Render from a clean copy of the sources, never from the working tree.
#
# terraform-docs reads initialised provider metadata when it is present, so a
# tree where someone has run `terraform init` renders the RESOLVED provider
# version (`4.8.0`) while a fresh checkout renders the CONSTRAINT (`~> 4.8.0`).
# Rendering in place would therefore make the CI drift check depend on whether
# the contributor happened to have initialised — output that flips based on
# untracked local state is not a gate, it is a coin toss. Copying only the
# tracked inputs makes the render a pure function of what is committed.
work="$tmp/render"
mkdir -p "$work"
cp "$ROOT"/*.tf "$work/"
cp "$ROOT/README.md" "$work/"

# `inject` rewrites only the region between the BEGIN_TF_DOCS / END_TF_DOCS
# markers, leaving the hand-written README around it alone.
"$tmp/terraform-docs" markdown table --output-file README.md --output-mode inject "$work"
cp "$work/README.md" "$ROOT/README.md"
echo "· README.md rendered with terraform-docs $VERSION"
