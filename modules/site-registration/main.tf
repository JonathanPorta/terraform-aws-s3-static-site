locals {
  key = "registrations/v1/${var.owner}/${var.service}/${var.environment}.json"

  overrides = merge(
    var.override_body_contains == null ? {} : { body_contains = var.override_body_contains },
    var.override_dns_resolver == null ? {} : { dns_resolver = var.override_dns_resolver },
    var.override_http_response_ms == null ? {} : { http_response_ms = var.override_http_response_ms },
  )

  # The document is exactly what registration.schema.json expects: optional
  # fields that are unset are left out, not written as null. jsonencode emits
  # object keys in lexical order, so the bytes are deterministic, and `checks`
  # is sorted so reordering the input is not a change.
  document = merge(
    {
      version           = 1
      owner             = var.owner
      service           = var.service
      environment       = var.environment
      enabled           = var.enabled
      url               = var.url
      hostname          = var.hostname
      registered_domain = var.registered_domain
      checks            = sort(var.checks)
    },
    var.id == null ? {} : { id = var.id },
    length(local.overrides) == 0 ? {} : { overrides = local.overrides },
  )

  content = jsonencode(local.document)
}

resource "aws_s3_object" "registration" {
  bucket       = var.registry_bucket
  key          = local.key
  content      = local.content
  content_type = "application/json"

  # Drift detection: the raw md5 of the content, which is the ETag S3 reports for
  # a single-part, non-KMS object. Refresh therefore compares the stored bytes to
  # the desired bytes, and an out-of-band edit of the document is reverted on the
  # next apply. The registry bucket uses SSE-S3; with SSE-KMS the ETag is not an
  # md5, so this would show a permanent diff (the bug the root module's README
  # documents) and `etag` would have to be replaced by `source_hash`, which only
  # detects local changes.
  etag = md5(local.content)

  # The registry bucket is BucketOwnerEnforced, and its writer contract is
  # bucket-owner-full-control (or no ACL): the canned ACL AWS documents as
  # accepted by such a bucket from any writer. AWS provider 4.8 cannot omit the
  # ACL (object.go: `acl` defaults to "private" and is copied into
  # UploadInput.ACL), so the contract value is set explicitly. It grants nothing
  # to anyone, since the bucket owner is the only owner. Verified live on
  # 2026-11-10: accepted. The default "private" was accepted too for a writer in
  # the bucket-owning account; another account was not tested. Provider 5.0
  # removed the default (so the argument could be omitted); the `~> 4.8.0` pin
  # keeps this explicit value correct.
  acl = "bucket-owner-full-control"

  tags = var.tags

  lifecycle {
    # Cross-variable rules cannot live in a variable validation before
    # Terraform 1.9, so they are preconditions on the one resource.
    precondition {
      condition     = split("/", trimprefix(var.url, "https://"))[0] == var.hostname
      error_message = "The host of url must equal hostname."
    }
    precondition {
      condition = (
        var.registered_domain == var.hostname ||
        (length(var.hostname) > length(var.registered_domain) &&
        substr(var.hostname, length(var.hostname) - length(var.registered_domain) - 1, length(var.registered_domain) + 1) == ".${var.registered_domain}")
      )
      error_message = "registered_domain must equal hostname or be a suffix of it on a label boundary."
    }
    precondition {
      condition     = length(local.content) <= 4096
      error_message = "The registration document must be at most 4096 bytes."
    }
  }
}
