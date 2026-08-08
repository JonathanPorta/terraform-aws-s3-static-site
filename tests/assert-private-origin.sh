#!/usr/bin/env bash
# assert-private-origin.sh — prove the opt-in private mode actually closes the
# origin, and prove that turning it off changes nothing for existing consumers.
#
# WHAT THIS RUNS AGAINST
#
# The module's own policy document, lifted out of main.tf at runtime by the same
# extract-don't-copy discipline tests/assert-composition.sh established. A
# hand-copied fixture can agree with main.tf on the lines someone thought to
# grep and disagree everywhere else; a derived one cannot drift at all.
#
# The static settings that are not policy — ownership, the four public-access-
# block flags, the bucket ACL resource, the object ACL — are asserted directly
# against main.tf, because they have no rendered artifact to inspect without
# credentials. Each assertion names the security property it protects, so a
# future edit that breaks one fails with the reason rather than a diff.
#
# NOT COVERED: a live apply. That needs a real bucket, real credentials, and a
# real CDN in front of it. Everything expressible without AWS is covered here;
# the end-to-end denial of a direct-origin request is the consumer's
# access-contract test, not this module's.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TFBIN="${TFBIN:-terraform}"
FIX="$HERE/private-origin"
GEN="$FIX/generated-module.tf"

pass=0; fail=0
ok() { echo "  ✓ $1"; pass=$((pass + 1)); }
no() { echo "  ✗ $1"; fail=$((fail + 1)); }
die() { echo "  ✗✗ $1" >&2; exit 1; }

cleanup() { rm -rf "$FIX/.terraform" "$FIX/.terraform.lock.hcl" "$FIX"/terraform.tfstate* "$FIX"/*.tfvars.json "$GEN"; }
trap cleanup EXIT
cleanup

extract_block() {
  awk -v pat="$2" '
    !on && $0 ~ pat { on = 1 }
    on {
      print
      line = $0; sub(/#.*/, "", line)
      depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line)
      if (depth == 0) exit
    }
  ' "$1"
}

# ── static settings: the four surfaces a policy check cannot see ─────────────
echo "── ACLs and public-access-block track the mode ──"

own_block="$(extract_block "$ROOT/main.tf" '^resource "aws_s3_bucket_ownership_controls"')"
printf '%s' "$own_block" | grep -q 'var.private_origin ? "BucketOwnerEnforced" : "ObjectWriter"' &&
  ok "private mode disables ACLs entirely (BucketOwnerEnforced)" ||
  no "ownership no longer switches to BucketOwnerEnforced in private mode — object ACLs would still be honoured"

pab_block="$(extract_block "$ROOT/main.tf" '^resource "aws_s3_bucket_public_access_block"')"
for flag in block_public_acls block_public_policy ignore_public_acls restrict_public_buckets; do
  if printf '%s' "$pab_block" | grep -qE "^[[:space:]]*${flag}[[:space:]]*=[[:space:]]*var\.private_origin[[:space:]]*$"; then
    ok "$flag follows the mode"
  else
    no "$flag is not bound to var.private_origin — a private bucket would keep a public-access hole"
  fi
done

acl_block="$(extract_block "$ROOT/main.tf" '^resource "aws_s3_bucket_acl" "app_bucket_acl"')"
printf '%s' "$acl_block" | grep -qE '^[[:space:]]*count[[:space:]]*=[[:space:]]*var\.private_origin \? 0 : 1' &&
  ok "no bucket ACL resource exists in private mode" ||
  no "the bucket ACL is still created in private mode — public-read would survive"

# Without this the address gains an index and every existing consumer sees a
# destroy/create on upgrade. "Backwards compatible" has to include state.
grep -qE '^\s*from\s*=\s*aws_s3_bucket_acl\.app_bucket_acl$' "$ROOT/main.tf" &&
  grep -qE '^\s*to\s*=\s*aws_s3_bucket_acl\.app_bucket_acl\[0\]$' "$ROOT/main.tf" &&
  ok "a moved block keeps the ACL address refactor out of existing consumers' plans" ||
  no "no moved block for the bucket ACL — upgrading consumers would see a destroy/create"

obj_block="$(extract_block "$ROOT/main.tf" '^resource "aws_s3_object" "app_bucket_source"')"
printf '%s' "$obj_block" | grep -qE '^[[:space:]]*acl[[:space:]]*=[[:space:]]*var\.private_origin \? null : "public-read"' &&
  ok "objects carry no ACL in private mode" ||
  no "objects still get a public-read ACL in private mode"

# ── render the policy against the pinned provider ────────────────────────────
echo "── the rendered policy ──"

builtin_block="$(extract_block "$ROOT/main.tf" '^data "aws_iam_policy_document" "app_bucket_public_read"')"
compose_block="$(extract_block "$ROOT/main.tf" '^data "aws_iam_policy_document" "app_bucket"[[:space:]]*\{')"
[ -n "$builtin_block" ] || die "could not find the built-in policy document in main.tf"

if ! printf '%s' "$builtin_block" | grep -q 'aws_s3_bucket\.app_bucket\.arn'; then
  die "the built-in document no longer references aws_s3_bucket.app_bucket.arn — the fixture's substitution is stale"
fi
builtin_block="${builtin_block//aws_s3_bucket.app_bucket.arn/var.bucket_arn}"

# The three private-origin variables are lifted too, so their validation rules
# are the module's real ones rather than a restatement of them.
for v in private_origin private_origin_allowed_cidrs private_origin_referer_secret extra_policy_documents; do
  blk="$(extract_block "$ROOT/variables.tf" "^variable \"$v\"")"
  [ -n "$blk" ] || die "could not find variable $v in variables.tf"
  printf '%s\n\n' "$blk"
done > "$GEN.vars"

{
  echo "# GENERATED by tests/assert-private-origin.sh from main.tf + variables.tf."
  echo "# Do not edit and do not commit; it is rewritten on every run."
  echo
  cat "$GEN.vars"
  echo "$builtin_block"
  echo
  echo "$compose_block"
} > "$GEN"
rm -f "$GEN.vars"

cd "$FIX"
"$TFBIN" init -backend=false -input=false > /dev/null
apply() { "$TFBIN" apply -auto-approve -input=false "$@" > /dev/null; }

CIDRS='["173.245.48.0/20","103.21.244.0/22","2400:cb00::/32"]'
SECRET='0123456789abcdef0123456789abcdef'

private_vars() {
  cat > private.tfvars.json <<JSON
{"private_origin": true,
 "private_origin_allowed_cidrs": $CIDRS,
 "private_origin_referer_secret": "$SECRET"}
JSON
}

echo "── public mode (the default) is unchanged ──"
apply
pub="$("$TFBIN" output -raw composed)"
[ "$(printf '%s' "$pub" | jq '.Statement[0] | has("Condition")')" = false ] &&
  ok "the default policy carries no condition" ||
  no "the default policy gained a condition — existing consumers would change"
[ "$(printf '%s' "$pub" | jq -r '.Statement[0].Principal')" = "*" ] &&
  ok "the default policy still grants Principal *" || no "the default principal changed"
legacy='{"Version":"2012-10-17","Statement":[{"Sid":"PublicReadGetObject","Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::example.test/*"}]}'
[ "$(printf '%s' "$pub" | jq -S -c .)" = "$(printf '%s' "$legacy" | jq -S -c .)" ] &&
  ok "the default rendered policy is byte-identical to the pre-change output" ||
  { no "the default rendered policy changed"; diff <(printf '%s' "$legacy" | jq -S .) <(printf '%s' "$pub" | jq -S .) || true; }

echo "── private mode restricts the origin ──"
private_vars
apply -var-file=private.tfvars.json
priv="$("$TFBIN" output -raw composed)"

[ "$(printf '%s' "$priv" | jq '.Statement | length')" = 1 ] &&
  ok "still exactly one statement" || no "unexpected statement count"
[ "$(printf '%s' "$priv" | jq -r '.Statement[0].Sid')" = PublicReadGetObject ] &&
  ok "the Sid is stable, so the documented override API works identically in both modes" ||
  no "the Sid changed between modes — the override contract would differ by mode"

# The load-bearing pair. Either one alone is a broken design, so both are
# asserted by name rather than by counting conditions.
if [ "$(printf '%s' "$priv" | jq -c '.Statement[0].Condition.IpAddress["aws:SourceIp"]')" = "$(printf '%s' "$CIDRS" | jq -c .)" ]; then
  ok "aws:SourceIp is bound to exactly the supplied CIDRs (this is what makes the policy non-public to AWS)"
else
  no "aws:SourceIp is missing or wrong — block_public_policy would reject the policy"
fi
# IAM renders every condition value as an array, including a single-valued one,
# so this reads the sole element rather than the key.
if [ "$(printf '%s' "$priv" | jq -r '.Statement[0].Condition.StringEquals["aws:Referer"] | if type=="array" then .[0] else . end')" = "$SECRET" ]; then
  ok "aws:Referer is bound to the origin secret (this is what excludes other tenants of the same CIDRs)"
else
  no "aws:Referer is missing — any other customer of the same CDN could reach the origin"
fi

echo "── contradictory and unsafe inputs are refused ──"
refuse() {
  local name="$1" json="$2" expect="$3"
  printf '%s' "$json" > bad.tfvars.json
  if out="$("$TFBIN" apply -auto-approve -input=false -var-file=bad.tfvars.json 2>&1)"; then
    no "$name was accepted"
  elif printf '%s' "$out" | grep -qi "$expect"; then
    ok "$name is refused"
  else
    no "$name failed for the wrong reason"; printf '%s\n' "$out" | tail -3 | sed 's/^/      /'
  fi
  rm -f bad.tfvars.json
}

refuse "an IPv4 range broader than /8" \
  '{"private_origin":true,"private_origin_allowed_cidrs":["10.0.0.0/4"],"private_origin_referer_secret":"'"$SECRET"'"}' \
  "evaluated as public"
refuse "an IPv6 range broader than /32" \
  '{"private_origin":true,"private_origin_allowed_cidrs":["2400::/16"],"private_origin_referer_secret":"'"$SECRET"'"}' \
  "evaluated as public"
refuse "a malformed CIDR" \
  '{"private_origin":true,"private_origin_allowed_cidrs":["not-a-cidr"],"private_origin_referer_secret":"'"$SECRET"'"}' \
  "valid CIDR"

echo
total=$((pass + fail))
[ "$fail" -eq 0 ] && { echo "private-origin: PASS ($total checks)"; exit 0; }
echo "private-origin: FAIL ($fail of $total)"; exit 1
