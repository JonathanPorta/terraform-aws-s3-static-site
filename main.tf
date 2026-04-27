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
# return 403, which surfaces as Cloudflare error 522 ("connection to origin")
# when the bucket is fronted by Cloudflare with SSL set to flexible.
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
}

resource "aws_s3_object" "app_bucket_source" {
  for_each = fileset(var.source_files, "**")
  bucket   = aws_s3_bucket.app_bucket.id
  key      = each.value
  source   = "${var.source_files}/${each.value}"
  etag     = filemd5("${var.source_files}/${each.value}")
  acl      = "public-read"
  content_type = (
    length(regexall("\\.[^.]+$", each.value)) > 0 ?
    lookup(local.mime_types, regex("\\.[^.]+$", each.value), local.default_mime_type) :
    local.default_mime_type
  )
}

resource "betteruptime_monitor" "this" {
  count             = local.provision_monitoring
  url               = "https://${var.hostname}"
  monitor_type      = "status"
  domain_expiration = 30
  follow_redirects  = true
  ssl_expiration    = 30
}
