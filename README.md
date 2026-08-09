# terraform-aws-s3-static-site

Very simple Terraform module for deploying a static site into an S3 bucket.

## Public access

This module **intentionally creates a public S3 website bucket**. Anonymous `s3:GetObject` is granted via:

- A bucket policy with `Principal: "*"` (the modern, post-2023 AWS approach)
- A bucket-level `public-read` ACL (legacy, retained for backwards compatibility)
- Per-object `public-read` ACLs on every uploaded file (legacy, retained)

If you don't want a publicly readable bucket, this module is the wrong tool — it's designed specifically for static website hosting where every object must be readable by anonymous clients.

### Account-level / organization-level Block Public Access

This module sets *bucket-level* `public_access_block` flags to `false`. **Account-level or organization-level S3 Block Public Access settings can still override that** and prevent the public-read bucket policy from being applied or taking effect, even after `terraform apply` reports success. If anonymous requests return `403` against an apparently-applied bucket, check:

```bash
# Account level (replace with your account id)
aws s3control get-public-access-block --account-id 123456789012

# Organization-level: your AWS Organizations admin will know.
```

If `BlockPublicPolicy` or `RestrictPublicBuckets` is `true` at account/org level, this module won't be able to make the bucket public until those flags are turned off.

### This module owns the bucket policy

S3 buckets have a single bucket-policy document. This module's `aws_s3_bucket_policy.app_bucket_public_read` resource will be the source of truth for that document — **do not attach a separate manual bucket policy** to buckets managed by this module, or your changes will be overwritten on the next `terraform apply`.

That overwrite is a genuinely dangerous failure mode when the out-of-band statement is a *security control*: it applies cleanly, appears to work, and is then silently reverted by an unrelated apply — removing the control with no signal, at exactly the moment you believe it is protecting you.

Since **1.5.0** you no longer need a fork. Contribute statements through `extra_policy_documents`:

```hcl
data "aws_iam_policy_document" "deny_insecure_transport" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [
      "arn:aws:s3:::www.example.com",
      "arn:aws:s3:::www.example.com/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

module "static_website" {
  source  = "JonathanPorta/s3-static-site/aws"
  version = "1.5.0"
  # ...

  extra_policy_documents = [
    data.aws_iam_policy_document.deny_insecure_transport.json,
  ]
}
```

The module still owns the single `aws_s3_bucket_policy` resource; your documents are merged into it through **`override_policy_documents`**, which gives the merge semantics you want:

| your document's `Sid` | result |
|---|---|
| unique | appended to the policy |
| `PublicReadGetObject` | **replaces** the module's built-in statement |

Caller documents cannot go in `source_policy_documents`: duplicate Sids there are a hard provider error (`duplicate Sid (PublicReadGetObject) in source_policy_documents`), so the "reuse the Sid to replace it" path would fail at plan time.

**What `aws_iam_policy_document` does and does not do for you.** It gives you structured HCL and deterministic JSON composition. It does **not** validate IAM semantics — a nonexistent action, a malformed resource ARN, an invented principal type, or an unknown condition operator all render successfully and are rejected later by **AWS**, when the policy is applied. Do not treat a clean plan as evidence that a policy is valid.

Both merge behaviours are covered by `tests/assert-composition.sh`, which runs against the module's pinned provider on CI.

Because the bucket ARN is an output of this module, referencing it inside a document you pass *in* would be circular. Construct the ARN from the hostname instead — `arn:aws:s3:::${var.hostname}` — since the bucket is named for its hostname.

### Upgrading from 1.4.0

With `extra_policy_documents` unset, the rendered policy is **semantically equivalent** to 1.4.0 and the `aws_s3_bucket_policy` resource address is unchanged, so no replacement or state-address churn is expected.

It is *not* byte-for-byte identical: the data source's rendered JSON differs from the previous `jsonencode` output, so expect at most a one-time in-place policy update on first apply.

### Content-Type drift detection

The `aws_s3_object` resource's `etag` attribute is what Terraform uses to decide whether a file needs to be re-uploaded. By default Terraform sets it to `filemd5(...)`, which means changes to the file *contents* trigger a re-upload but changes to derived metadata (like `content_type`) do not.

This module composes the etag from **both** the file md5 and the derived content type:

```hcl
etag = md5(join("|", [
  filemd5(...),
  local.source_content_types[each.value]
]))
```

That way, if the mime mapping changes (e.g. the module ships a new entry in `mime.json`, or you upgrade from an older module version that defaulted JPGs to `application/octet-stream`), the next `terraform apply` re-uploads the affected objects with the correct `Content-Type` header.

The first `terraform apply` after upgrading to a module version that includes this fix will re-upload **every** existing object once, even if its content type is already correct. Subsequent applies are no-ops.

### Private origin (opt-in)

Set `private_origin = true` to serve the bucket to a fronting CDN only, instead of to the public internet. It is off by default and changes nothing for existing consumers.

```hcl
module "site" {
  # ...
  private_origin                = true
  private_origin_allowed_cidrs  = ["173.245.48.0/20", "103.21.244.0/22", "2400:cb00::/32"]
  private_origin_referer_secret = var.origin_secret  # >= 32 chars, keep it out of VCS
}
```

In this mode the module sets `object_ownership = "BucketOwnerEnforced"`, enables **all four** public-access-block settings, creates no `aws_s3_bucket_acl`, sets no object ACLs, and conditions the read policy on **both** `aws:SourceIp` and `aws:Referer`.

**Both conditions are load-bearing.** AWS evaluates a bucket policy as public unless it grants access only to fixed values of an enumerated set of condition keys. `aws:SourceIp` with fixed CIDRs is on that list, which is what lets a `Principal: "*"` statement survive `block_public_policy = true`. `aws:Referer` is *not* on that list, so a Referer-only policy would still be evaluated as public and rejected. Conversely, a CDN's egress ranges are shared by all of its tenants, so `aws:SourceIp` alone authenticates "some tenant", not yours — anyone could point their own zone at your origin. The shared secret is what binds the origin to your zone.

AWS also treats `aws:SourceIp` ranges broader than `/8` (IPv4) or `/32` (IPv6) as public. The module rejects those at plan time rather than letting the apply fail with a distant error.

Two caveats worth knowing before you adopt it:

- **The origin hop is HTTP.** S3 website endpoints do not serve HTTPS. Your CDN terminates TLS for the user; CDN-to-origin is plaintext.
- **The secret is in Terraform state.** A policy condition value is part of the resource, so it cannot be kept out of state. The variable is marked `sensitive` (so it stays out of CLI output), but your state backend is the real boundary. Rotate by changing the value and re-applying — no data migration.

Upgrading is a no-op for public consumers: the bucket ACL gains a `count` index, and a `moved` block tells Terraform that is a refactor rather than a replace, so no state migration is required.

### v2 roadmap (planned)

Private mode already adopts the modern posture — `BucketOwnerEnforced`, no ACLs, policy as the sole access-control mechanism — but only when opted into. A future v2 will make it the default for *public* sites too:

- Switch ownership to `BucketOwnerEnforced` unconditionally
- Remove the `aws_s3_bucket_acl` resource
- Remove `acl = "public-read"` from `aws_s3_object` resources
- Rely entirely on `aws_s3_bucket_policy` for public access

That remains a breaking change for public consumers, which is why it stays deferred to a major version bump.

## Development

Four checks run on every PR, and all four are runnable locally:

```sh
bash tests/assert-composition.sh        # bucket-policy merge semantics, against the pinned provider
bash tests/assert-private-origin.sh     # private mode closes the origin; the public default is unchanged
bash tests/assert-actions-pinned.sh     # every third-party GitHub Action is pinned to a commit SHA
bash tests/next-version.sh --self-test  # the arithmetic that names a release
bash tests/render-docs.sh               # regenerate the block below, then commit the result
```

Releases are cut by `.github/workflows/terraform-publish.yaml` from the merged PR's `major` / `minor` /
`patch` label. `bash tests/next-version.sh minor` prints the tag that would produce.

`render-docs.sh` is a step you have to remember, because CI checks the rendered README rather than
pushing it for you. That is deliberate: the action that used to push it delegated to a mutable
container tag and held write access to the branch under review. A README that changed because an
input's contract changed belongs in the diff a reviewer reads, not in a commit CI appends afterwards.

## Module Documentation

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 4.8.0 |
| <a name="requirement_betteruptime"></a> [betteruptime](#requirement\_betteruptime) | ~> 0.3.15 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 4.8.0 |
| <a name="provider_betteruptime"></a> [betteruptime](#provider\_betteruptime) | ~> 0.3.15 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_s3_bucket.app_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_acl.app_bucket_acl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_acl) | resource |
| [aws_s3_bucket_ownership_controls.app_bucket_acl_ownership](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.app_bucket_public_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.app_bucket_public_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_versioning.app_bucket_versioning](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_website_configuration.app_bucket_website](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_website_configuration) | resource |
| [aws_s3_object.app_bucket_source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [betteruptime_monitor.this](https://registry.terraform.io/providers/BetterStackHQ/better-uptime/latest/docs/resources/monitor) | resource |
| [aws_iam_policy_document.app_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.app_bucket_public_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | The name of the environment that this static site belongs to. e.g. [staging, production] | `string` | n/a | yes |
| <a name="input_error_document_key"></a> [error\_document\_key](#input\_error\_document\_key) | The optional name of the error document to use for the bucket. | `string` | `"index.html"` | no |
| <a name="input_extra_policy_documents"></a> [extra\_policy\_documents](#input\_extra\_policy\_documents) | Additional IAM policy documents to compose into this bucket's single policy,<br/>as rendered JSON — typically `data.aws_iam_policy_document.<name>.json`.<br/><br/>A bucket has exactly one policy and this module owns it, so a consumer cannot<br/>declare a second `aws_s3_bucket_policy`, and must not apply one out of band<br/>(the next apply would silently revert it). Contribute statements here instead.<br/><br/>Authoring them as `aws_iam_policy_document` data sources gives you structured<br/>HCL and deterministic JSON composition. It does NOT validate IAM semantics:<br/>unknown actions, malformed resources, invented principal types, and unknown<br/>condition operators all render fine and are rejected later by AWS, when the<br/>policy is applied.<br/><br/>Supplied to `override_policy_documents`, so a document with a unique Sid is<br/>appended and one reusing `PublicReadGetObject` replaces the built-in<br/>statement. (They cannot go in `source_policy_documents`: duplicate Sids there<br/>are a hard provider error.)<br/><br/>Default `[]` yields a policy semantically equivalent to pre-1.5.0 and leaves<br/>the `aws_s3_bucket_policy` resource address unchanged, so no replacement or<br/>state-address churn is expected. The rendered JSON is not byte-for-byte<br/>identical to the previous `jsonencode` output. | `list(string)` | `[]` | no |
| <a name="input_hostname"></a> [hostname](#input\_hostname) | The FQDN where this static site will be accessible. | `string` | n/a | yes |
| <a name="input_index_document_suffix"></a> [index\_document\_suffix](#input\_index\_document\_suffix) | The optional name of the index document to use for the bucket. | `string` | `"index.html"` | no |
| <a name="input_monitoring"></a> [monitoring](#input\_monitoring) | Whether or not to enable monitoring. | `bool` | `false` | no |
| <a name="input_private_origin"></a> [private\_origin](#input\_private\_origin) | Serve the site to a fronting CDN only, instead of to the public internet.<br/><br/>When true the module sets object\_ownership = "BucketOwnerEnforced", enables<br/>ALL FOUR public-access-block settings, creates no bucket ACL, sets no object<br/>ACLs, and conditions the read policy on BOTH the caller's egress CIDRs<br/>(aws:SourceIp) AND a shared origin secret (aws:Referer).<br/><br/>Requires private\_origin\_allowed\_cidrs and private\_origin\_referer\_secret.<br/>Leaving it false changes nothing about this module's behaviour. | `bool` | `false` | no |
| <a name="input_private_origin_allowed_cidrs"></a> [private\_origin\_allowed\_cidrs](#input\_private\_origin\_allowed\_cidrs) | Egress CIDR blocks permitted to read the bucket in private mode, normally<br/>the fronting CDN's published ranges.<br/><br/>Pinned in source rather than fetched at apply time, so a change to the<br/>security boundary is a reviewable diff instead of a silent drift. A stale<br/>list fails closed. | `list(string)` | `[]` | no |
| <a name="input_private_origin_referer_secret"></a> [private\_origin\_referer\_secret](#input\_private\_origin\_referer\_secret) | Shared secret the fronting CDN must send as the Referer header on every<br/>origin request in private mode. At least 32 characters.<br/><br/>This is what distinguishes THIS CDN zone from every other tenant of the same<br/>egress ranges; the CIDR allowlist alone authenticates the CDN, not the<br/>account. Rotate by changing this value and re-applying — no data migration.<br/><br/>Note: a bucket policy condition value is necessarily part of the resource,<br/>so this appears in Terraform state and in plan output. Mark your state<br/>backend accordingly. `sensitive` keeps it out of CLI output and logs. | `string` | `null` | no |
| <a name="input_routing_rule_key_prefix_equals"></a> [routing\_rule\_key\_prefix\_equals](#input\_routing\_rule\_key\_prefix\_equals) | The optional key prefix to match. | `string` | `null` | no |
| <a name="input_routing_rule_replace_key_with"></a> [routing\_rule\_replace\_key\_with](#input\_routing\_rule\_replace\_key\_with) | The optional name key to replace with. | `string` | `null` | no |
| <a name="input_source_files"></a> [source\_files](#input\_source\_files) | A path to the website's source files. These will be uploaded to the bucket. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket"></a> [bucket](#output\_bucket) | The name of the bucket that will server this site. |
| <a name="output_bucket_fqdn"></a> [bucket\_fqdn](#output\_bucket\_fqdn) | The FQDN of the bucket that will serve this static site. |
| <a name="output_environment"></a> [environment](#output\_environment) | The environment that this static site belongs to. |
| <a name="output_hostname"></a> [hostname](#output\_hostname) | The FQDN where this static site will be accessible. (Also becomes the bucket name.)) |
<!-- END_TF_DOCS -->
