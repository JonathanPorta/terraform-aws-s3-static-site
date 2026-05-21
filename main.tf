# Site Bucket Setup and Permissions
resource "aws_s3_bucket" "app_bucket" {
  bucket = var.hostname
  tags = {
    Name        = var.hostname
    Environment = var.environment
  }
}

resource "aws_s3_bucket_ownership_controls" "app_bucket_acl_ownership" {
  bucket = aws_s3_bucket.app_bucket.id
  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_public_access_block" "app_bucket_public_access" {
  bucket = aws_s3_bucket.app_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "app_bucket_acl" {
  depends_on = [
    aws_s3_bucket_ownership_controls.app_bucket_acl_ownership,
    aws_s3_bucket_public_access_block.app_bucket_public_access,
  ]

  bucket = aws_s3_bucket.app_bucket.id
  acl    = "public-read"
}

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
resource "aws_s3_bucket_policy" "app_bucket_public_read" {
  depends_on = [
    aws_s3_bucket_public_access_block.app_bucket_public_access,
  ]

  bucket = aws_s3_bucket.app_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.app_bucket.arn}/*"
    }]
  })
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
  # Compose the file md5 with the derived content_type so a change to the
  # mime mapping (e.g. this module ships a new mime.json entry) forces a
  # re-upload, even when the underlying bytes are unchanged. Without this,
  # objects originally uploaded under an older module version stay stuck
  # with their original content_type (often application/octet-stream),
  # which breaks downstream features that depend on a correct MIME type
  # (e.g. social-card image previews on iMessage / Facebook / Slack).
  etag = md5(join("|", [
    filemd5("${var.source_files}/${each.value}"),
    local.source_content_types[each.value]
  ]))
  acl          = "public-read"
  content_type = local.source_content_types[each.value]
}

resource "betteruptime_monitor" "this" {
  count             = local.provision_monitoring
  url               = "https://${var.hostname}"
  monitor_type      = "status"
  domain_expiration = 30
  follow_redirects  = true
  ssl_expiration    = 30
}
