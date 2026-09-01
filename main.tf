# Site Bucket Setup and Permissions
resource "aws_s3_bucket" "app_bucket" {
  bucket = var.hostname
  tags = {
    Name        = var.hostname
    Environment = var.environment
  }
}

# ObjectWriter keeps ACLs usable, which the public mode depends on.
# BucketOwnerEnforced disables ACLs entirely — the modern guidance this
# module's README lists as its v2 roadmap item — and private mode adopts it
# now, because an origin that still honours object ACLs is not private.
resource "aws_s3_bucket_ownership_controls" "app_bucket_acl_ownership" {
  bucket = aws_s3_bucket.app_bucket.id
  rule {
    object_ownership = var.private_origin ? "BucketOwnerEnforced" : "ObjectWriter"
  }
}

resource "aws_s3_bucket_public_access_block" "app_bucket_public_access" {
  bucket = aws_s3_bucket.app_bucket.id

  # All four are the inverse of the mode. Public mode must leave them off or
  # its public-read ACL and unconditional policy are rejected; private mode
  # turns all four on, which is only possible because the private policy
  # qualifies as non-public (see the aws:SourceIp note on the policy document).
  block_public_acls       = var.private_origin
  block_public_policy     = var.private_origin
  ignore_public_acls      = var.private_origin
  restrict_public_buckets = var.private_origin
}

# Absent entirely in private mode: with BucketOwnerEnforced, applying any
# bucket ACL is an error, and a "private" bucket carrying a public-read ACL
# would be a contradiction rather than a hardening.
#
# The `moved` block below keeps this from churning existing consumers' state
# when they upgrade: the address gains an index, and Terraform is told that is
# a refactor rather than a replace.
resource "aws_s3_bucket_acl" "app_bucket_acl" {
  count = var.private_origin ? 0 : 1

  depends_on = [
    aws_s3_bucket_ownership_controls.app_bucket_acl_ownership,
    aws_s3_bucket_public_access_block.app_bucket_public_access,
  ]

  bucket = aws_s3_bucket.app_bucket.id
  acl    = "public-read"
}

moved {
  from = aws_s3_bucket_acl.app_bucket_acl
  to   = aws_s3_bucket_acl.app_bucket_acl[0]
}

# ── Bucket policy ────────────────────────────────────────────────────────────
#
# Public-read bucket policy. The ACL approach above (acl = "public-read") was
# the canonical pattern when this module was first written, but AWS has been
# progressively deprecating public-read ACLs since April 2023. New buckets
# created today often have ACL-based public access silently fail at the
# request level — the ACL applies but anonymous GetObject requests still
# return 403. When this bucket is fronted by a CDN, that underlying S3 403
# can surface as confusing edge/origin behavior during rollout.
#
# Adding an explicit aws_s3_bucket_policy is the modern, reliable equivalent.
# Bucket policy + ACL coexist fine; the policy is what actually grants
# public read in the post-2023 AWS world. depends_on the public-access-block
# so the policy isn't rejected by a "block public policy" setting that races
# with creation.
#
# COMPOSING ADDITIONAL STATEMENTS
#
# A bucket has exactly ONE policy, and `aws_s3_bucket_policy` REPLACES it — it
# does not append. A consumer that needs extra statements (a write-once prefix,
# a per-principal confinement) therefore cannot add a second
# `aws_s3_bucket_policy` resource, and must not apply one out of band: the next
# `terraform apply` would silently revert it, removing the control with no
# signal. That failure mode is worst exactly where these statements matter most.
#
# So the policy is composed here instead. The module keeps sole ownership of the
# resource; consumers contribute statements through `var.extra_policy_documents`.
#
# WHAT THE PROVIDER DOES AND DOES NOT CHECK
#
# `aws_iam_policy_document` gives callers structured HCL and deterministic JSON
# composition. It does NOT validate IAM semantics: a nonexistent action, a
# malformed resource, an invented principal type, or an unknown condition
# operator all render successfully and fail later, at AWS, during the resource
# operation. AWS remains the authority on whether a policy means anything.
data "aws_iam_policy_document" "app_bucket_public_read" {
  statement {
    sid       = "PublicReadGetObject"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.app_bucket.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    # PRIVATE MODE — why both conditions, and why these two specifically.
    #
    # aws:SourceIp is what makes this policy legal at all. AWS evaluates a
    # bucket policy as public unless it grants access only to fixed values of an
    # enumerated set of condition keys; aws:SourceIp with fixed CIDRs is on that
    # list, so a Principal "*" statement conditioned on it is treated as
    # NON-public and survives block_public_policy = true. aws:Referer is NOT on
    # that list — a Referer-only policy would still be evaluated as public and
    # rejected, so private mode would fail to apply.
    #
    # aws:Referer is what makes the IP allowlist mean anything. Cloudflare's
    # egress ranges are shared by every Cloudflare customer, so SourceIp alone
    # authenticates "some Cloudflare account", not this one; anyone could point
    # their own zone at the origin and be inside the range. The shared secret is
    # what binds the origin to the caller's zone.
    #
    # Neither is sufficient alone, so both are emitted together or not at all.
    dynamic "condition" {
      for_each = var.private_origin ? [1] : []
      content {
        test     = "IpAddress"
        variable = "aws:SourceIp"
        values   = var.private_origin_allowed_cidrs
      }
    }

    dynamic "condition" {
      for_each = var.private_origin ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:Referer"
        values   = [var.private_origin_referer_secret]
      }
    }
  }
}

# SOURCE vs OVERRIDE — this distinction is load-bearing, not stylistic.
#
# Documents merged through `source_policy_documents` must have mutually unique
# Sids: the pinned provider (v4.8.0) hard-errors with
# `duplicate Sid (PublicReadGetObject) in source_policy_documents`. So putting
# caller documents there would make the documented "reuse the Sid to replace the
# built-in statement" path fail at PLAN time — a public API promise the module
# could not keep.
#
# `override_policy_documents` has the merge semantics actually wanted: a
# statement with a unique Sid is appended, and one reusing an earlier Sid
# REPLACES it. Hence built-in as the source, callers as overrides.
#
# Verified against provider 4.8.0 by tests/policy-composition.
data "aws_iam_policy_document" "app_bucket" {
  source_policy_documents   = [data.aws_iam_policy_document.app_bucket_public_read.json]
  override_policy_documents = var.extra_policy_documents
}

# NOTE: the resource address is unchanged (`app_bucket_public_read`) so existing
# state does not churn on upgrade. Its name now understates what it holds; the
# rename is deliberately deferred to avoid a destroy/create on every consumer.
resource "aws_s3_bucket_policy" "app_bucket_public_read" {
  depends_on = [
    aws_s3_bucket_public_access_block.app_bucket_public_access,
  ]

  bucket = aws_s3_bucket.app_bucket.id
  policy = data.aws_iam_policy_document.app_bucket.json

  # Contradictory inputs fail at PLAN time rather than producing a bucket that
  # is neither properly public nor properly private. Terraform cannot express
  # cross-variable checks in a `validation` block, so they live here.
  lifecycle {
    precondition {
      condition     = var.private_origin || (length(var.private_origin_allowed_cidrs) == 0 && var.private_origin_referer_secret == null)
      error_message = "private_origin_allowed_cidrs and private_origin_referer_secret are only meaningful when private_origin = true. Set private_origin = true or remove them."
    }
    precondition {
      condition     = !var.private_origin || length(var.private_origin_allowed_cidrs) > 0
      error_message = "private_origin = true requires a non-empty private_origin_allowed_cidrs. An empty allowlist would leave the origin reachable from nowhere, or — if the condition were dropped — from everywhere."
    }
    precondition {
      condition     = !var.private_origin || (var.private_origin_referer_secret != null && length(var.private_origin_referer_secret) >= 32)
      error_message = "private_origin = true requires private_origin_referer_secret of at least 32 characters. Without it the allowlist authenticates any Cloudflare customer, not this zone."
    }
  }
}

resource "aws_s3_bucket_versioning" "app_bucket_versioning" {
  bucket = aws_s3_bucket.app_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_website_configuration" "app_bucket_website" {
  bucket = aws_s3_bucket.app_bucket.id

  index_document {
    suffix = var.index_document_suffix
  }

  error_document {
    key = var.error_document_key
  }
  # routing_rule {}
  dynamic "routing_rule" {
    for_each = var.routing_rule_key_prefix_equals != null && var.routing_rule_key_prefix_equals != null ? [1] : []
    content {
      condition {
        key_prefix_equals = var.routing_rule_key_prefix_equals
      }
      redirect {
        replace_key_with = var.routing_rule_replace_key_with
      }
    }
  }
}

locals {
  default_mime_type    = "application/octet-stream"
  mime_types           = jsondecode(file("${path.module}/mime.json"))
  provision_monitoring = var.monitoring == true ? 1 : 0
  source_file_paths    = fileset(var.source_files, "**")
  # Map every source file to the content type derived from its extension.
  # Computed once here so the same value drives both `aws_s3_object.content_type`
  # and the change-detection etag below.
  source_content_types = {
    for f in local.source_file_paths : f => (
      length(regexall("\\.[^.]+$", f)) > 0 ?
      lookup(local.mime_types, regex("\\.[^.]+$", f), local.default_mime_type) :
      local.default_mime_type
    )
  }
}

resource "aws_s3_object" "app_bucket_source" {
  for_each = local.source_file_paths
  bucket   = aws_s3_bucket.app_bucket.id
  key      = each.value
  source   = "${var.source_files}/${each.value}"
  # The raw file md5, which is what S3 itself reports as the ETag for a
  # single-part upload. Anything else can never converge: S3 returns its own
  # ETag, refresh writes that into state, and the next plan wants the computed
  # value again — a permanent diff that re-uploads every object on every apply.
  #
  # A changed MIME mapping still forces an upload. `content_type` is a managed
  # argument, and provider 4.8.0 counts it as an object-content change in
  # hasS3ObjectContentChanges(), so the re-upload happens through that argument
  # rather than by folding metadata into the remote ETag.
  etag = filemd5("${var.source_files}/${each.value}")
  # null omits the ACL entirely. Required in private mode: under
  # BucketOwnerEnforced, sending any object ACL is a hard error.
  acl          = var.private_origin ? null : "public-read"
  content_type = local.source_content_types[each.value]

  # Order uploads AFTER the ownership control (re-enables ACLs) and the public-
  # access block (permits public ACLs). On a brand-new bucket these objects
  # otherwise upload in parallel and race ahead of those settings, failing with
  # "AccessControlListNotSupported: The bucket does not allow ACLs" until a
  # second apply. (Dropping the object ACL entirely — making this depends_on
  # unnecessary — is the v2 roadmap item; see README.)
  depends_on = [
    aws_s3_bucket_ownership_controls.app_bucket_acl_ownership,
    aws_s3_bucket_public_access_block.app_bucket_public_access,
  ]
}

resource "betteruptime_monitor" "this" {
  count             = local.provision_monitoring
  url               = "https://${var.hostname}"
  monitor_type      = "status"
  domain_expiration = 30
  follow_redirects  = true
  ssl_expiration    = 30
}
