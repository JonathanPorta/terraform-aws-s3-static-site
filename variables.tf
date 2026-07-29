variable "hostname" {
  type        = string
  description = "The FQDN where this static site will be accessible."
}
variable "environment" {
  type        = string
  description = "The name of the environment that this static site belongs to. e.g. [staging, production]"
}
variable "source_files" {
  description = "A path to the website's source files. These will be uploaded to the bucket."
  type        = string
}
variable "routing_rule_key_prefix_equals" {
  description = "The optional key prefix to match."
  type        = string
  default     = null
}
variable "routing_rule_replace_key_with" {
  description = "The optional name key to replace with."
  type        = string
  default     = null
}
variable "index_document_suffix" {
  description = "The optional name of the index document to use for the bucket."
  type        = string
  default     = "index.html"
}
variable "error_document_key" {
  description = "The optional name of the error document to use for the bucket."
  type        = string
  default     = "index.html"
}
variable "monitoring" {
  description = "Whether or not to enable monitoring."
  type        = bool
  default     = false

}

variable "extra_policy_documents" {
  description = <<-EOT
    Additional IAM policy documents to compose into this bucket's single policy,
    as rendered JSON — typically `data.aws_iam_policy_document.<name>.json`.

    A bucket has exactly one policy and this module owns it, so a consumer cannot
    declare a second `aws_s3_bucket_policy`, and must not apply one out of band
    (the next apply would silently revert it). Contribute statements here instead.

    Authoring them as `aws_iam_policy_document` data sources gives you structured
    HCL and deterministic JSON composition. It does NOT validate IAM semantics:
    unknown actions, malformed resources, invented principal types, and unknown
    condition operators all render fine and are rejected later by AWS, when the
    policy is applied.

    Supplied to `override_policy_documents`, so a document with a unique Sid is
    appended and one reusing `PublicReadGetObject` replaces the built-in
    statement. (They cannot go in `source_policy_documents`: duplicate Sids there
    are a hard provider error.)

    Default `[]` yields a policy semantically equivalent to pre-1.5.0 and leaves
    the `aws_s3_bucket_policy` resource address unchanged, so no replacement or
    state-address churn is expected. The rendered JSON is not byte-for-byte
    identical to the previous `jsonencode` output.
  EOT
  type        = list(string)
  default     = []
}
