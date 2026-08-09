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

# ── Private origin (opt-in) ──────────────────────────────────────────────────
#
# Off by default. Every existing consumer keeps the public behaviour it has
# today, byte for byte in its rendered policy and unchanged in its state — see
# tests/assert-private-origin.sh, which proves both.

variable "private_origin" {
  description = <<-EOT
    Serve the site to a fronting CDN only, instead of to the public internet.

    When true the module sets object_ownership = "BucketOwnerEnforced", enables
    ALL FOUR public-access-block settings, creates no bucket ACL, sets no object
    ACLs, and conditions the read policy on BOTH the caller's egress CIDRs
    (aws:SourceIp) AND a shared origin secret (aws:Referer).

    Requires private_origin_allowed_cidrs and private_origin_referer_secret.
    Leaving it false changes nothing about this module's behaviour.
  EOT
  type        = bool
  default     = false
}

variable "private_origin_allowed_cidrs" {
  description = <<-EOT
    Egress CIDR blocks permitted to read the bucket in private mode, normally
    the fronting CDN's published ranges.

    Pinned in source rather than fetched at apply time, so a change to the
    security boundary is a reviewable diff instead of a silent drift. A stale
    list fails closed.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for c in var.private_origin_allowed_cidrs :
      can(cidrhost(c, 0))
    ])
    error_message = "Every entry must be a valid CIDR block."
  }

  # AWS evaluates a Principal "*" policy conditioned on aws:SourceIp as PUBLIC
  # when the ranges are "broader than /8 for IPv4 and /32 for IPv6". A policy
  # that trips that bound is rejected by block_public_policy, so private mode
  # would fail to apply — with an AWS-side error far from its cause. Catch it
  # here instead.
  validation {
    condition = alltrue([
      for c in var.private_origin_allowed_cidrs :
      length(regexall(":", c)) > 0 ? tonumber(split("/", c)[1]) >= 32 : tonumber(split("/", c)[1]) >= 8
    ])
    error_message = "CIDR ranges broader than /8 (IPv4) or /32 (IPv6) are evaluated as public by AWS block-public-access and would make private mode unappliable."
  }
}

variable "private_origin_referer_secret" {
  description = <<-EOT
    Shared secret the fronting CDN must send as the Referer header on every
    origin request in private mode. At least 32 characters.

    This is what distinguishes THIS CDN zone from every other tenant of the same
    egress ranges; the CIDR allowlist alone authenticates the CDN, not the
    account. Rotate by changing this value and re-applying — no data migration.

    Note: a bucket policy condition value is necessarily part of the resource,
    so this appears in Terraform state and in plan output. Mark your state
    backend accordingly. `sensitive` keeps it out of CLI output and logs.
  EOT
  type        = string
  default     = null
  sensitive   = true
}
