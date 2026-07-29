#!/usr/bin/env bash
# assert-composition.sh — prove the bucket-policy merge semantics the module
# documents are the semantics the pinned provider actually implements.
#
# The claim under test used to be wrong. An earlier revision put caller documents
# in `source_policy_documents` while documenting that reusing a Sid would
# override the built-in statement. Provider 4.8.0 rejects duplicate Sids there
# outright, so that documented path failed at plan time. This fixture exists so
# that cannot regress silently.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TFBIN="${TFBIN:-terraform}"
FIX="$HERE/policy-composition"

pass=0; fail=0
ok() { echo "  ✓ $1"; pass=$((pass+1)); }
no() { echo "  ✗ $1"; fail=$((fail+1)); }

echo "── the fixture mirrors the module (anti-drift) ──"
# A fixture that has drifted from main.tf proves nothing about main.tf.
mod="$(sed 's/#.*//' "$ROOT/main.tf")"
if printf '%s' "$mod" | grep -q 'source_policy_documents   = \[data.aws_iam_policy_document.app_bucket_public_read.json\]'; then
  ok "module sources ONLY its built-in document"
else
  no "module no longer sources exactly its built-in document — the fixture may not reflect it"
fi
if printf '%s' "$mod" | grep -q 'override_policy_documents = var.extra_policy_documents'; then
  ok "module passes caller documents as OVERRIDES"
else
  no "module no longer passes caller documents via override_policy_documents"
fi
if printf '%s' "$mod" | grep -q 'sid       = "PublicReadGetObject"'; then
  ok "module's built-in Sid is still PublicReadGetObject"
else
  no "module's built-in Sid changed — update the fixture mirror"
fi

echo "── render against the pinned provider ──"
cd "$FIX"
rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
"$TFBIN" init -backend=false -input=false >/dev/null
"$TFBIN" apply -auto-approve -input=false >/dev/null   # data sources only; creates nothing
ver="$("$TFBIN" version -json | jq -r '.provider_selections["registry.terraform.io/hashicorp/aws"] // .provider_selections["registry.opentofu.org/hashicorp/aws"] // "unknown"')"
echo "  · aws provider $ver"
case "$ver" in 4.8.*) ok "provider matches the module's pin" ;; *) no "provider is $ver, expected 4.8.x" ;; esac

j() { "$TFBIN" output -raw "$1"; }

echo "── default: one statement, unchanged meaning ──"
d="$(j composed_default)"
[ "$(printf '%s' "$d" | jq '.Statement | length')" = 1 ] &&
  ok "exactly one statement" || no "expected exactly one statement"
[ "$(printf '%s' "$d" | jq -r '.Statement[0].Sid')" = PublicReadGetObject ] &&
  ok "Sid is PublicReadGetObject" || no "wrong Sid"
[ "$(printf '%s' "$d" | jq -r '.Statement[0].Effect')" = Allow ] &&
  ok "Effect is Allow" || no "wrong Effect"

echo "── unique Sid: appended, built-in untouched ──"
u="$(j composed_unique)"
[ "$(printf '%s' "$u" | jq '.Statement | length')" = 2 ] &&
  ok "two statements" || no "expected two statements, got $(printf '%s' "$u" | jq '.Statement|length')"
printf '%s' "$u" | jq -e '.Statement[] | select(.Sid=="DenyInsecureTransport")' >/dev/null &&
  ok "the caller statement was appended" || no "the caller statement is missing"
printf '%s' "$u" | jq -e '.Statement[] | select(.Sid=="PublicReadGetObject") | select(.Effect=="Allow")' >/dev/null &&
  ok "the built-in statement survives unchanged" || no "the built-in statement was altered"

echo "── duplicate Sid: caller REPLACES the built-in ──"
o="$(j composed_override)"
[ "$(printf '%s' "$o" | jq '.Statement | length')" = 1 ] &&
  ok "still exactly one statement (replaced, not appended)" ||
  no "expected one statement, got $(printf '%s' "$o" | jq '.Statement|length')"
[ "$(printf '%s' "$o" | jq -r '.Statement[0].Effect')" = Deny ] &&
  ok "the caller's Effect (Deny) won" || no "the built-in Allow survived — override did not take effect"

echo "── the default is SEMANTICALLY equivalent, not byte-identical ──"
# The PR previously claimed byte-identity with 1.4.0. It is false, and stating a
# stronger guarantee than holds is how a real incompatibility later gets waved
# through. What actually holds: same meaning, same resource address.
legacy='{"Version":"2012-10-17","Statement":[{"Sid":"PublicReadGetObject","Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::example.test/*"}]}'
if [ "$(printf '%s' "$d" | jq -S -c .)" = "$(printf '%s' "$legacy" | jq -S -c .)" ]; then
  ok "default is semantically equivalent to the pre-1.5.0 jsonencode output"
else
  no "default is NOT semantically equivalent to pre-1.5.0"
  diff <(printf '%s' "$legacy" | jq -S .) <(printf '%s' "$d" | jq -S .) || true
fi
[ "$d" != "$legacy" ] &&
  ok "and NOT byte-identical — the weaker, true claim is the documented one" ||
  ok "byte-identical too (still fine; the docs claim only equivalence)"

rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
echo
total=$((pass+fail))
[ "$fail" -eq 0 ] && { echo "policy-composition: PASS ($total checks)"; exit 0; }
echo "policy-composition: FAIL ($fail of $total)"; exit 1
