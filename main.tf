# Site Bucket Setup and Permissions
resource "aws_s3_bucket" "app_bucket" {
  bucket = var.hostname
  tags = {
    Name        = var.hostname
    Environment = var.environment
  }
}
resource "aws_s3_bucket_acl" "app_bucket_acl" {
  bucket = aws_s3_bucket.app_bucket.id
  acl    = "public-read"
}
resource "aws_s3_bucket_versioning" "app_bucket_versioning" {
  bucket = aws_s3_bucket.app_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_policy" "app_bucket_policy" {
  bucket = aws_s3_bucket.app_bucket.id
  policy = data.aws_iam_policy_document.app_bucket_policy.json
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
  # routing_rule {
  #   condition {
  #     key_prefix_equals = var.routing_rule_key_prefix_equals
  #   }
  #   redirect {
  #     replace_key_with = var.routing_rule_replace_key_with
  #   }
  # }
  # routing_rules = var.routing_rule
  # dynamic "routing_rule" {
  #   for_each = var.routing_rule
  #   condition {
  #     http_error_code_returned_results = routing_rule.value.Condition.HttpErrorCodeReturnedEquals
  #     key_prefix_equals                = routing_rule.value.Condition.KeyPrefixEquals
  #   }
  #   redirect {
  #     host_name               = routing_rule.value.Redirect.HostName
  #     http_redirect_code      = routing_rule.value.Redirect.HttpRedirectCode
  #     protocol                = routing_rule.value.Redirect.Protocol
  #     replace_key_prefix_with = routing_rule.value.Redirect.ReplaceKeyPrefixWith
  #     replace_key_with        = routing_rule.value.Redirect.ReplaceKeyWith
  #   }
  # }
}

locals {
  mime_types = jsondecode(file("${path.module}/mime.json"))
}

resource "aws_s3_object" "app_bucket_source" {
  for_each     = fileset(var.source_files, "**")
  bucket       = aws_s3_bucket.app_bucket.id
  key          = each.value
  source       = "${var.source_files}/${each.value}"
  etag         = filemd5("${var.source_files}/${each.value}")
  acl          = "public-read"
  content_type = lookup(local.mime_types, regex("\\.[^.]+$", each.value), null)
}

data "aws_iam_policy_document" "app_bucket_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.app_bucket.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}
