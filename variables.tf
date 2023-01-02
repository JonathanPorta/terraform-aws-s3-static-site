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

# variable "routing_rule" {
#   description = "An optional list of routing rules to apply to the bucket."
#   type        = string
#   # list(object({
#   #   Condition = object({
#   #     HttpErrorCodeReturnedEquals = string
#   #     KeyPrefixEquals             = string
#   #   })
#   #   Redirect = object({
#   #     HostName             = string
#   #     HttpRedirectCode     = string
#   #     Protocol             = string
#   #     ReplaceKeyPrefixWith = string
#   #     ReplaceKeyWith       = string
#   #   })
#   # }))
#   default = ""
# }

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
