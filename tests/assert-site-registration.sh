#!/usr/bin/env bash
# assert-site-registration.sh — prove modules/site-registration stores exactly
# the document the registration contract expects, and rejects what it forbids.
#
# WHAT THIS RUNS AGAINST
#
# The submodule itself, called from tests/site-registration/main.tf the way a
# consumer calls it, planned with the pinned AWS provider (4.8.0). `terraform
# plan -refresh=false` on a new resource makes no AWS call, so no credentials
# are needed. Negative cases are plans that must fail with the module's own
# error message; a plan that fails for any other reason does not count.
#
# NOT COVERED: a live apply (needs the registry bucket and the IAM grant), and
# the monitoring host's reconciler, which validates the stored document again.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TFBIN="${TFBIN:-terraform}"
FIX="$HERE/site-registration"
MOD="$ROOT/modules/site-registration"
SCHEMA="$FIX/registration.schema.json"

pass=0; fail=0
ok() { echo "  ✓ $1"; pass=$((pass + 1)); }
no() { echo "  ✗ $1"; fail=$((fail + 1)); }
die() { echo "  ✗✗ $1" >&2; exit 1; }

cleanup() {
  rm -rf "$FIX/.terraform" "$FIX/.terraform.lock.hcl" "$FIX"/terraform.tfstate* \
         "$FIX"/plan.tfplan "$HERE"/site-registration-control/.terraform "$HERE"/site-registration-control/.terraform.lock.hcl "$HERE"/site-registration-control/plan.tfplan "$FIX"/case.tfvars.json "$FIX"/plan.log \
         "$MOD/.terraform" "$MOD/.terraform.lock.hcl"
}
trap cleanup EXIT
cleanup

echo "── the submodule validates on its own ──"
( cd "$MOD" && "$TFBIN" init -backend=false -input=false >/dev/null 2>&1 && "$TFBIN" validate >/dev/null 2>&1 ) \
  && ok "terraform init -backend=false && terraform validate in modules/site-registration" \
  || no "the submodule does not validate"

( cd "$FIX" && "$TFBIN" init -backend=false -input=false >/dev/null 2>&1 ) || die "fixture init failed"
ok "fixture initialised with the pinned provider"

# run_plan <json-inputs>  -> 0 and plan.tfplan on success, else non-zero with plan.log
run_plan() {
  printf '{"inputs": %s}\n' "$1" > "$FIX/case.tfvars.json"
  ( cd "$FIX" && "$TFBIN" plan -input=false -refresh=false -no-color \
      -var-file=case.tfvars.json -out=plan.tfplan >plan.log 2>&1 )
}
plan_json() { ( cd "$FIX" && "$TFBIN" show -json plan.tfplan ); }
# obj_attr <attribute>  (reads plan JSON on stdin)
obj_attr() {
  python3 -c "
import json,sys
p=json.load(sys.stdin)
for c in p['resource_changes']:
    if c['type']=='aws_s3_object':
        v=c['change']['after'].get(sys.argv[1])
        print('' if v is None else v)
" "$1"
}
md5_of() { printf '%s' "$1" | { md5 -q 2>/dev/null || md5sum | awk '{print $1}'; }; }

echo "── 1. full document: key, bytes, content type, etag ──"
FULL='{"id":"docsort-production","enabled":true,"checks":["tls","http","domain","dns"],
       "override_http_response_ms":5000,"override_body_contains":"DocSort","override_dns_resolver":"1.1.1.1:53"}'
run_plan "$FULL" || { cat "$FIX/plan.log"; die "plan of the full example failed"; }
PJ="$(plan_json)"
content="$(printf '%s' "$PJ" | obj_attr content)"
expect='{"checks":["dns","domain","http","tls"],"enabled":true,"environment":"production","hostname":"www.docsort.io","id":"docsort-production","overrides":{"body_contains":"DocSort","dns_resolver":"1.1.1.1:53","http_response_ms":5000},"owner":"JonathanPorta","registered_domain":"docsort.io","service":"docsort.io","url":"https://www.docsort.io/","version":1}'
[ "$content" = "$expect" ] && ok "stored bytes are the deterministic, sorted-key document" \
  || { no "stored document differs"; echo "      got:  $content"; echo "      want: $expect"; }
[ "$(printf '%s' "$PJ" | obj_attr key)" = "registrations/v1/JonathanPorta/docsort.io/production.json" ] \
  && ok "key is registrations/v1/<owner>/<service>/<environment>.json" || no "wrong key"
[ "$(printf '%s' "$PJ" | obj_attr content_type)" = "application/json" ] \
  && ok "content_type is application/json" || no "wrong content_type"
[ "$(printf '%s' "$PJ" | obj_attr etag)" = "$(md5_of "$content")" ] \
  && ok "etag is the raw md5 of the content (drift detection)" || no "etag is not md5(content)"
# The upload ACL: provider 4.8 copies `acl` into the PutObject request (default
# "private"), and a BucketOwnerEnforced bucket accepts only an omitted ACL or
# bucket-owner-full-control (S3 Object Ownership docs). The rule is encoded as a
# table and checked against the ACL in the plan, the value the provider sends.
acl_accepted() { python3 - "$1" <<'PY'
import sys
ACCEPTED = {"", "bucket-owner-full-control"}   # "" = omitted
sys.exit(0 if sys.argv[1] in ACCEPTED else 1)
PY
}
for a in "" bucket-owner-full-control; do
  acl_accepted "$a" && ok "rule table: '${a:-<omitted>}' is accepted by an owner-enforced bucket" || no "rule table rejects '${a:-<omitted>}'"
done
for a in private public-read public-read-write authenticated-read aws-exec-read bucket-owner-read log-delivery-write; do
  acl_accepted "$a" && no "rule table accepts '$a'" || ok "rule table: '$a' is rejected by an owner-enforced bucket"
done
mod_acl="$(printf '%s' "$PJ" | obj_attr acl)"
acl_accepted "$mod_acl" && ok "the module's planned upload ACL ('$mod_acl') is accepted by an owner-enforced bucket" \
  || no "the module's planned upload ACL ('$mod_acl') would be rejected"
[ "$mod_acl" = "bucket-owner-full-control" ] && ok "the planned ACL is bucket-owner-full-control" || no "planned ACL is '$mod_acl'"
# Negative control: the same check must reject a bare aws_s3_object with the
# provider 4.8 default, and with an explicit public-read.
CTL="$HERE/site-registration-control"
( cd "$CTL" && "$TFBIN" init -backend=false -input=false >/dev/null 2>&1 ) || die "control init failed"
for acl_in in default public-read; do
  args=(); [ "$acl_in" != default ] && args=(-var "acl=$acl_in")
  ( cd "$CTL" && "$TFBIN" plan -input=false -refresh=false -no-color ${args[@]+"${args[@]}"} -out=plan.tfplan >/dev/null 2>&1 ) || die "control plan failed"
  c_acl="$( cd "$CTL" && "$TFBIN" show -json plan.tfplan | obj_attr acl )"
  if acl_accepted "$c_acl"; then no "negative control ($acl_in): ACL '$c_acl' passed the check"; else ok "negative control ($acl_in): ACL '$c_acl' is rejected by the check"; fi
done
rm -rf "$CTL/.terraform" "$CTL/.terraform.lock.hcl" "$CTL/plan.tfplan" "$CTL"/terraform.tfstate*
[ "$(printf '%s' "$PJ" | python3 -c 'import json,sys; print(json.load(sys.stdin)["planned_values"]["outputs"]["document"]["value"]==json.loads(sys.argv[1]))' "$content")" = "True" ] \
  && ok "the document output is the decoded content" || no "document output differs from content"
printf '%s' "$content" > "$FIX/doc-full.json.tmp"

echo "── 2. minimal document: omitted optionals are left out, defaults apply ──"
run_plan '{}' || { cat "$FIX/plan.log"; die "plan of the minimal example failed"; }
content_min="$(plan_json | obj_attr content)"
expect_min='{"checks":["dns","domain","http","tls"],"enabled":true,"environment":"production","hostname":"www.docsort.io","owner":"JonathanPorta","registered_domain":"docsort.io","service":"docsort.io","url":"https://www.docsort.io/","version":1}'
[ "$content_min" = "$expect_min" ] && ok "no id, no overrides, all four checks, enabled true" \
  || { no "minimal document differs"; echo "      got:  $content_min"; }
printf '%s' "$content_min" > "$FIX/doc-min.json.tmp"

echo "── 3. enabled=false keeps the registration ──"
run_plan '{"enabled":false}' || { cat "$FIX/plan.log"; die "plan with enabled=false failed"; }
c3="$(plan_json | obj_attr content)"
printf '%s' "$c3" | grep -q '"enabled":false' && ok "document is still planned, with \"enabled\":false" || no "enabled=false did not produce a document"

echo "── 4. check order does not change the bytes ──"
run_plan '{"checks":["domain","tls","dns","http"]}' || die "plan failed"
[ "$(plan_json | obj_attr content)" = "$content_min" ] && ok "reordered checks plan the identical document" || no "check order leaks into the document"

echo "── 5. generated documents satisfy the contract's JSON Schema ──"
if python3 -c 'import jsonschema' 2>/dev/null; then
  for f in doc-full doc-min; do
    python3 - "$SCHEMA" "$FIX/$f.json.tmp" <<'PY' && ok "$f validates against registration.schema.json" || no "$f violates registration.schema.json"
import json,sys,jsonschema
jsonschema.validate(json.load(open(sys.argv[2])), json.load(open(sys.argv[1])))
PY
  done
else
  echo "  - python jsonschema is not installed; schema validation skipped (the expected-bytes cases above still pin the shape)"
fi
rm -f "$FIX"/doc-*.json.tmp

echo "── 6. invalid inputs fail the plan with the module's own message ──"
# reject <label> <json-inputs> <expected message fragment>
reject() {
  if run_plan "$2"; then no "$1: accepted"; return; fi
  if grep -qF -- "$3" "$FIX/plan.log"; then ok "$1"; else no "$1: failed, but not with '$3'"; sed -n 1,12p "$FIX/plan.log"; fi
}
reject "owner with a leading hyphen"      '{"owner":"-bad"}'                               "owner must match"
reject "owner with a slash"               '{"owner":"a/b"}'                                "owner must match"
reject "owner over 39 characters"         "{\"owner\":\"a$(printf 'b%.0s' $(seq 1 39))\"}" "owner must match"
reject "service in upper case"            '{"service":"DocSort.io"}'                       "service must match"
reject "service with .."                  '{"service":"a..b"}'                             "service must match"
reject "service with a slash"             '{"service":"a/b"}'                              "service must match"
reject "environment with a dot"           '{"environment":"prod.1"}'                       "environment must match"
reject "environment with a trailing -"    '{"environment":"prod-"}'                        "environment must match"
reject "bucket name upper case"           '{"registry_bucket":"Registry"}'                 "registry_bucket must be"
reject "http URL"                         '{"url":"http://www.docsort.io/"}'               "url must be an https"
reject "URL with a port"                  '{"url":"https://www.docsort.io:8443/"}'         "url must be an https"
reject "URL with credentials"             '{"url":"https://u:p@www.docsort.io/"}'          "url must be an https"
reject "URL with a query"                 '{"url":"https://www.docsort.io/?a=1"}'          "url must be an https"
reject "URL with a fragment"              '{"url":"https://www.docsort.io/#x"}'            "url must be an https"
reject "URL over 200 characters"          "{\"url\":\"https://www.docsort.io/$(printf 'a%.0s' $(seq 1 190))\"}" "url must be an https"
reject "URL host differs from hostname"   '{"url":"https://other.docsort.io/"}'            "host of url must equal hostname"
reject "hostname in upper case"           '{"hostname":"WWW.docsort.io","url":"https://WWW.docsort.io/"}' "hostname must be a lowercase"
reject "single-label hostname"            '{"hostname":"docsort","url":"https://docsort/","registered_domain":"docsort.io"}' "must be a lowercase"
reject "IP literal hostname"              '{"hostname":"192.168.1.10","url":"https://192.168.1.10/","registered_domain":"168.1.10"}' "must not be an IP literal"
reject "reserved suffix .internal"        '{"hostname":"app.corp.internal","url":"https://app.corp.internal/","registered_domain":"corp.internal"}' "must not be an IP literal"
reject "reserved suffix .ts.net"          '{"hostname":"box.tail1.ts.net","url":"https://box.tail1.ts.net/","registered_domain":"tail1.ts.net"}' "must not be an IP literal"
reject "registered_domain not a suffix"   '{"registered_domain":"example.org"}'            "registered_domain must equal hostname or be a suffix"
reject "registered_domain mid-label"      '{"hostname":"www.xdocsort.io","url":"https://www.xdocsort.io/","registered_domain":"docsort.io"}' "registered_domain must equal hostname or be a suffix"
reject "registered_domain longer"         '{"registered_domain":"a.www.docsort.io"}'       "registered_domain must equal hostname or be a suffix"
reject "empty checks"                     '{"checks":[]}'                                  "checks must be non-empty"
reject "duplicate checks"                 '{"checks":["http","http"]}'                     "checks must be non-empty and must not contain duplicates"
reject "unknown check"                    '{"checks":["http","ping"]}'                     "checks may only contain"
reject "id in upper case"                 '{"id":"Docsort"}'                               "id must match"
reject "id with a dot"                    '{"id":"doc.sort"}'                              "id must match"
reject "response bound below 500"         '{"override_http_response_ms":499}'              "between 500 and 30000"
reject "response bound above 30000"       '{"override_http_response_ms":30001}'            "between 500 and 30000"
reject "fractional response bound"        '{"override_http_response_ms":1500.5}'           "between 500 and 30000"
reject "body_contains with a quote"       '{"override_body_contains":"a\"b"}'              "override_body_contains must be"
reject "body_contains with a newline"     '{"override_body_contains":"a\nb"}'              "override_body_contains must be"
reject "body_contains with a dollar"      '{"override_body_contains":"a$b"}'               "override_body_contains must be"
reject "body_contains with a bracket"     '{"override_body_contains":"[a]"}'               "override_body_contains must be"
reject "empty body_contains"              '{"override_body_contains":""}'                  "override_body_contains must be"
reject "body_contains over 100 characters" "{\"override_body_contains\":\"$(printf 'a%.0s' $(seq 1 101))\"}" "override_body_contains must be"
reject "resolver not on the list"         '{"override_dns_resolver":"8.8.8.9:53"}'         "override_dns_resolver must be"
reject "resolver without a port"          '{"override_dns_resolver":"1.1.1.1"}'            "override_dns_resolver must be"

echo "── 6b. boundary values the schema allows are accepted ──"
accept() { run_plan "$2" && ok "$1" || { no "$1: rejected"; sed -n 1,12p "$FIX/plan.log"; }; }
accept "response bound 500"               '{"override_http_response_ms":500}'
accept "response bound 30000"             '{"override_http_response_ms":30000}'
accept "body_contains with every allowed punctuation" '{"override_body_contains":"A b._,:;!?@#%&+/~-9"}'
accept "owner of 39 characters"           "{\"owner\":\"a$(printf 'b%.0s' $(seq 1 38))\"}"
accept "registered_domain equal to hostname" '{"hostname":"docsort.io","url":"https://docsort.io","registered_domain":"docsort.io"}'
accept "URL with a path"                  '{"url":"https://www.docsort.io/health/check"}'

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
