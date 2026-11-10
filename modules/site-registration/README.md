# site-registration

Registers one site/environment with the monitoring server by storing a small, non-secret JSON document in a private registry bucket. The monitoring server turns each document into HTTP, DNS, TLS-expiry and domain-expiry checks. Creating, changing, disabling or destroying the module therefore creates, changes, disables or removes the site's checks.

The module is one `aws_s3_object`. It needs only the `hashicorp/aws` provider (`~> 4.8.0`, the same pin as the root module) and Terraform `>= 1.2`. It has no AWS data sources, creates no IAM, and never touches Terraform state.

> **Terraform success means the registration is STORED, not applied.** The monitoring server reads the registry on a schedule (every few minutes) and reports separately, through its own status page and metrics, when it has applied a registration. Until then the previous checks keep running.

The document contract is the JSON Schema `registry/registration.schema.json` and `docs/site-registration.md` in the `monitoring.porta.codes` repository; where they disagree the schema wins. `tests/site-registration/registration.schema.json` here is a copy used by the tests.

## Usage

```hcl
module "registration" {
  source  = "JonathanPorta/s3-static-site/aws//modules/site-registration"
  version = "~> 1.7" # pin to the release that contains this module

  registry_bucket   = "my-monitoring-registry"
  owner             = "JonathanPorta"
  service           = "docsort.io" # normally the site's APP_NAME
  environment       = "production"
  url               = "https://www.docsort.io/"
  hostname          = "www.docsort.io"
  registered_domain = "docsort.io"

  # Optional:
  # checks                    = ["http", "tls"]
  # id                        = "docsort-production"
  # override_http_response_ms  = 5000
  # override_body_contains    = "DocSort"
  # override_dns_resolver     = "1.1.1.1:53"
}
```

This stores `registrations/v1/JonathanPorta/docsort.io/production.json`:

```json
{"checks":["dns","domain","http","tls"],"enabled":true,"environment":"production","hostname":"www.docsort.io","owner":"JonathanPorta","registered_domain":"docsort.io","service":"docsort.io","url":"https://www.docsort.io/","version":1}
```

Keys are in lexical order (what `jsonencode` produces), `checks` is sorted, and unset optional fields are left out.

## Lifecycle

| Action | Effect |
|---|---|
| apply | The document is written (create or overwrite). |
| `enabled = false` | The document is kept with `"enabled": false`. The monitoring server removes the checks; the registration remains. |
| `checks` without a type | The matching checks are removed. |
| `terraform destroy` (or removing the module) | The object is deleted. The checks are removed once the monitoring server has read the registry completely and confirmed it is gone. |

## Drift detection

`etag = md5(content)`. For a single-part object stored without KMS, S3 reports the raw md5 as the ETag, so every refresh compares the stored bytes with the desired bytes: an out-of-band edit is reverted by the next apply, and a deleted object is re-created (this needs `s3:ListBucket`, see below). The registry bucket uses SSE-S3 (the bucket default); **with SSE-KMS the ETag is not an md5 and this would show a permanent diff.** If the bucket ever moves to KMS, replace `etag` with `source_hash`, which only detects changes made through Terraform. The module sets `acl = "bucket-owner-full-control"` explicitly: see the next section.

## Object ACL

The registry bucket is `BucketOwnerEnforced` (ACLs disabled). S3 then accepts an upload only with no ACL or with `bucket-owner-full-control`, and rejects any other ACL, including `private`, with HTTP 400 `AccessControlListNotSupported` ([Object Ownership](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)). AWS provider 4.8 cannot omit the ACL: `acl` defaults to `private` and is copied into the upload (`internal/service/s3/object.go`). The module therefore sets `acl = "bucket-owner-full-control"`. This is the writer contract for the registry bucket. Provider 5.0 removed the default and 6.x still has `acl`, so a later provider bump does not break this; the `~> 4.8.0` constraint is unchanged.

Live acceptance of this by the real bucket has not been demonstrated yet; the tests check the planned ACL only.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `registry_bucket` | `string` | required | Registry bucket name. |
| `owner` | `string` | required | GitHub owner; `^[A-Za-z0-9][A-Za-z0-9-]{0,38}$`. |
| `service` | `string` | required | Service name (normally `APP_NAME`); `^[a-z0-9]([a-z0-9.-]{0,61}[a-z0-9])?$`, no `..`. |
| `environment` | `string` | required | `^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$`. |
| `url` | `string` | required | `https://` only, at most 200 characters, no credentials, port, query or fragment; its host must equal `hostname`. |
| `hostname` | `string` | required | Lowercase public DNS name, at least two labels; not an IP literal, `localhost`, or `.local`, `.internal`, `.ts.net`, `.lan`, `.test`, `.example`, `.invalid`. |
| `registered_domain` | `string` | required | Equal to `hostname` or a suffix of it on a label boundary. |
| `checks` | `list(string)` | all four | Non-empty, duplicate-free subset of `http`, `dns`, `tls`, `domain`. |
| `enabled` | `bool` | `true` | `false` keeps the document with `"enabled": false`. |
| `id` | `string` | `null` | Optional site id override (slug, unique across registrations). |
| `override_http_response_ms` | `number` | `null` | Integer 500..30000. |
| `override_body_contains` | `string` | `null` | 1..100 characters from ``A-Za-z0-9 ._,:;!?@#%&+/~-``. |
| `override_dns_resolver` | `string` | `null` | One of `1.1.1.1:53`, `1.0.0.1:53`, `8.8.8.8:53`, `8.8.4.4:53`, `9.9.9.9:53`, `149.112.112.112:53`, `208.67.222.222:53`, `208.67.220.220:53`. |
| `tags` | `map(string)` | `{}` | Object tags. Non-empty tags need `s3:PutObjectTagging`. |

The overrides are three nullable variables rather than one object with `optional()` attributes, because `optional()` needs Terraform 1.3 and this repository supports `>= 1.2`. The checks that compare two inputs (URL host against `hostname`, `registered_domain` against `hostname`, the 4096-byte document limit) are `precondition`s on the resource for the same reason: a variable validation may not reference another variable before Terraform 1.9. All of them fail at plan time.

## Outputs

| Name | Description |
|---|---|
| `bucket` | The registry bucket. |
| `key` | The object key, `registrations/v1/<owner>/<service>/<environment>.json`. |
| `document` | The stored document, decoded. |
| `version_id` | The S3 version id (null when the bucket is not versioned). |

## IAM permissions the calling identity needs

Only on this site's own keys, `arn:aws:s3:::<registry_bucket>/registrations/v1/<owner>/<service>/*`. These are the calls the AWS provider 4.8 `aws_s3_object` makes:

| Action | Used for |
|---|---|
| `s3:PutObject` | create, update (and `s3:PutObjectTagging` when `tags` is non-empty or the provider sets `default_tags`) |
| `s3:PutObjectAcl` | an upload that carries an ACL header needs it in addition to `s3:PutObject` (S3 API permissions table for PutObject, <https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-with-s3-policy-actions.html>), and the module always sends `bucket-owner-full-control`. It cannot make any other ACL valid and confers no access, because the bucket owner is the only owner |
| `s3:GetObject` | refresh (`HeadObject`) |
| `s3:GetObjectTagging` | refresh, on every refresh even with no tags |
| `s3:PutObjectTagging`, `s3:DeleteObjectTagging` | tag changes |
| `s3:DeleteObject` | destroy |
| `s3:DeleteObjectVersion` | destroy on a versioned bucket (each version is deleted) |
| `s3:ListBucket` on the bucket, with `s3:prefix` limited to the same prefix | a missing object reads as 404 instead of 403, so an out-of-band deletion is seen and repaired |
| `s3:ListBucketVersions` on the bucket, same prefix condition | destroy on a versioned bucket |

`ruam.sh` (blessed-cicd, 1.2.0 and later) writes exactly this grant into a site's `<APP_NAME>-ci` policy when `MONITORING_REGISTRY_BUCKET` and `MONITORING_REGISTRY_OWNER` are set. No other site's registration is readable, listable, writable or deletable with it, and it grants nothing on Terraform state.
