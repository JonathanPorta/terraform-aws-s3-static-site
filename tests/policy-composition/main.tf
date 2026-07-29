# Static half of the bucket-policy regression fixture.
#
# The half that matters — the built-in statement, the composing document, and
# the `extra_policy_documents` variable — is NOT here. It is extracted verbatim
# from the module by tests/assert-composition.sh into `generated-module.tf` on
# every run.
#
# That is deliberate. This file used to hand-copy the module's policy documents,
# and the drift guard was three greps for individual lines. A copy that agrees
# with `main.tf` on those three lines and disagrees everywhere else still passed,
# and — the concrete hole — the fixture never touched
# `aws_s3_bucket_policy.app_bucket_public_read` at all, so reverting that
# resource to consume the *uncomposed* document would have dropped every caller
# statement while all checks stayed green. Deriving the fixture removes the
# copy, and so removes the possibility of it drifting.
#
# What remains here is only what has no counterpart in the module: a credential-
# free provider, the caller-supplied documents that stand in for a consumer, and
# the outputs. The provider constraint is pinned to the SAME range as the module
# because the behaviour under test is provider behaviour — v4.8.0 hard-errors on
# duplicate Sids in `source_policy_documents`, which is the whole reason caller
# documents go to `override_policy_documents`. A fixture on a newer provider
# could pass while the module's pinned provider fails.
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

# Stands in for `aws_s3_bucket.app_bucket.arn`, which cannot be evaluated
# without creating a bucket. assert-composition.sh rewrites that one reference
# to this variable when it extracts the module's document, and fails if the
# reference it expected to rewrite was not there.
variable "bucket_arn" {
  type    = string
  default = "arn:aws:s3:::example.test"
}

# ── what a consumer passes in ────────────────────────────────────────────────

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

# ── outputs ──────────────────────────────────────────────────────────────────

# `composed` is the module's own composing document, extracted from main.tf.
# The three cases are driven by re-applying with different values of
# `var.extra_policy_documents` — the module's actual public API — rather than by
# three separately-wired copies of the composition.
output "composed" {
  value = data.aws_iam_policy_document.app_bucket.json
}

output "builtin" {
  value = data.aws_iam_policy_document.app_bucket_public_read.json
}

output "unique_sid_json" {
  value = data.aws_iam_policy_document.unique_sid.json
}

output "duplicate_sid_json" {
  value = data.aws_iam_policy_document.duplicate_sid.json
}
