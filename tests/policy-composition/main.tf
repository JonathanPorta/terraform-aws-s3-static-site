# Regression fixture for the module's bucket-policy composition.
#
# It pins the SAME AWS provider constraint as the module, because the behaviour
# under test is provider behaviour: v4.8.0 hard-errors on duplicate Sids in
# `source_policy_documents`, which is precisely why caller documents must go to
# `override_policy_documents`. A fixture on a newer provider could pass while the
# module's pinned provider fails.
#
# No AWS resources, no credentials, no network: `aws_iam_policy_document` is
# rendered locally by the provider.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.8.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock-access-key"
  secret_key                  = "mock-secret-key"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

variable "bucket_arn" {
  type    = string
  default = "arn:aws:s3:::example.test"
}

# Mirrors the module's built-in statement. tests/assert-composition.sh checks
# that this mirror has not drifted from main.tf.
data "aws_iam_policy_document" "built_in" {
  statement {
    sid       = "PublicReadGetObject"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

# A caller document with a UNIQUE Sid — must be APPENDED.
data "aws_iam_policy_document" "unique_sid" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["${var.bucket_arn}/*"]

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

# A caller document REUSING the built-in Sid — must REPLACE it.
data "aws_iam_policy_document" "duplicate_sid" {
  statement {
    sid       = "PublicReadGetObject"
    effect    = "Deny"
    actions   = ["s3:GetObject"]
    resources = ["${var.bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

# ── the exact wiring main.tf uses ────────────────────────────────────────────

data "aws_iam_policy_document" "composed_default" {
  source_policy_documents   = [data.aws_iam_policy_document.built_in.json]
  override_policy_documents = []
}

data "aws_iam_policy_document" "composed_unique" {
  source_policy_documents   = [data.aws_iam_policy_document.built_in.json]
  override_policy_documents = [data.aws_iam_policy_document.unique_sid.json]
}

data "aws_iam_policy_document" "composed_override" {
  source_policy_documents   = [data.aws_iam_policy_document.built_in.json]
  override_policy_documents = [data.aws_iam_policy_document.duplicate_sid.json]
}

output "composed_default" { value = data.aws_iam_policy_document.composed_default.json }
output "composed_unique" { value = data.aws_iam_policy_document.composed_unique.json }
output "composed_override" { value = data.aws_iam_policy_document.composed_override.json }
