# Static half of the private-origin regression fixture.
#
# The half that matters — the built-in policy document, the composing document,
# and the private-origin variables with their validation rules — is NOT here.
# It is extracted verbatim from the module by tests/assert-private-origin.sh
# into `generated-module.tf` on every run, for the same reason
# tests/policy-composition does it: a hand-copied fixture drifts, and a fixture
# that drifts proves something other than what it claims.
#
# The provider is pinned to the SAME range as the module because the behaviour
# under test is provider behaviour — how `aws_iam_policy_document` renders a
# dynamic condition block. A fixture on a newer provider could pass while the
# module's pinned provider fails.
#
# No AWS resources, no credentials, no network: `aws_iam_policy_document` is
# rendered locally by the provider.

terraform {
  required_version = ">= 1.2"

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
# without creating a bucket. assert-private-origin.sh rewrites that one
# reference when it extracts the module's document, and fails if the reference
# it expected to rewrite was not there.
variable "bucket_arn" {
  type    = string
  default = "arn:aws:s3:::example.test"
}

output "composed" {
  value = data.aws_iam_policy_document.app_bucket.json
}

output "builtin" {
  value = data.aws_iam_policy_document.app_bucket_public_read.json
}
