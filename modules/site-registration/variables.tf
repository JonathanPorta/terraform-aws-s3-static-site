# Every rule here mirrors registry/registration.schema.json and
# docs/site-registration.md in the monitoring.porta.codes repository (the
# contract). The JSON Schema wins where the two disagree. The monitoring host
# validates again when it reads the document; these checks exist so a bad value
# fails at plan time instead of being stored and then rejected by the reconciler.

variable "registry_bucket" {
  description = "Name of the private registry bucket the registration is stored in."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.registry_bucket))
    error_message = "registry_bucket must be a valid S3 bucket name (3-63 characters: lowercase letters, digits, dots, hyphens)."
  }
}

variable "owner" {
  description = "GitHub owner (user or organisation) of the site. Part of the key and of the document; the calling identity may only write under its own owner/service."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", var.owner))
    error_message = "owner must match ^[A-Za-z0-9][A-Za-z0-9-]{0,38}$ (mixed case allowed)."
  }
}

variable "service" {
  description = "Service name, normally the site's APP_NAME (for example docsort.io). Part of the key and of the document."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]{0,61}[a-z0-9])?$", var.service)) && !can(regex("\\.\\.", var.service))
    error_message = "service must match ^[a-z0-9]([a-z0-9.-]{0,61}[a-z0-9])?$ and must not contain \"..\"."
  }
}

variable "environment" {
  description = "Environment name (for example production). Part of the key and of the document."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", var.environment))
    error_message = "environment must match ^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$."
  }
}

variable "url" {
  description = "URL to monitor. https only, no credentials, port, query or fragment; its host must equal hostname."
  type        = string

  validation {
    condition = (
      can(regex("^https://[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+(/[\\x21\\x24-\\x3e\\x40-\\x7e]*)?$", var.url))
      && length(var.url) <= 200
    )
    error_message = "url must be an https:// URL (at most 200 characters) with a lowercase DNS host of at least two labels and no credentials, port, query or fragment."
  }
}

variable "hostname" {
  description = "Public DNS name being monitored: lowercase, at least two labels, not an IP literal, not localhost and not a reserved suffix (.local, .internal, .ts.net, .lan, .test, .example, .invalid). Must equal the host of url."
  type        = string

  validation {
    condition = (
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.hostname))
      && length(var.hostname) <= 253
    )
    error_message = "hostname must be a lowercase DNS name of at least two labels (at most 253 characters)."
  }

  # Not in the JSON Schema pattern, but docs/site-registration.md lists them and
  # the reconciler rejects them; failing here saves a stored-but-invalid document.
  validation {
    condition = (
      !can(regex("^[0-9]+(\\.[0-9]+){3}$", var.hostname))
      && !can(regex("(^|\\.)localhost$", var.hostname))
      && !can(regex("\\.(local|internal|ts\\.net|lan|test|example|invalid)$", var.hostname))
    )
    error_message = "hostname must not be an IP literal, localhost, or end in .local, .internal, .ts.net, .lan, .test, .example or .invalid."
  }
}

variable "registered_domain" {
  description = "The registered domain the domain-expiry check belongs to. Must equal hostname or be a suffix of it (on a label boundary). Not checked against the public-suffix list."
  type        = string

  validation {
    condition = (
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.registered_domain))
      && length(var.registered_domain) <= 253
    )
    error_message = "registered_domain must be a lowercase DNS name of at least two labels (at most 253 characters)."
  }
}

variable "checks" {
  description = "Checks the monitoring server should run: a non-empty, duplicate-free subset of http, dns, tls, domain."
  type        = list(string)
  default     = ["http", "dns", "tls", "domain"]
  nullable    = false

  validation {
    condition     = length(var.checks) >= 1 && length(distinct(var.checks)) == length(var.checks)
    error_message = "checks must be non-empty and must not contain duplicates."
  }

  validation {
    condition     = alltrue([for c in var.checks : contains(["http", "dns", "tls", "domain"], c)])
    error_message = "checks may only contain http, dns, tls and domain."
  }
}

variable "enabled" {
  description = "When false the document is kept with \"enabled\": false: the monitoring server removes the checks but the registration remains."
  type        = bool
  default     = true
  nullable    = false
}

variable "id" {
  description = "Optional stable site id override (a slug, unique across registrations). Defaults on the monitoring side to the slug of <service>-<environment>."
  type        = string
  default     = null

  validation {
    condition     = var.id == null ? true : can(regex("^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$", var.id))
    error_message = "id must match ^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$."
  }
}

# Optional overrides are three nullable variables rather than one object with
# optional() attributes, because optional() needs Terraform 1.3 and this repo
# supports >= 1.2. All null means no "overrides" key in the document.

variable "override_http_response_ms" {
  description = "Optional override: HTTP response-time bound in milliseconds (integer, 500..30000)."
  type        = number
  default     = null

  validation {
    condition     = var.override_http_response_ms == null ? true : (var.override_http_response_ms == floor(var.override_http_response_ms) && var.override_http_response_ms >= 500 && var.override_http_response_ms <= 30000)
    error_message = "override_http_response_ms must be an integer between 500 and 30000."
  }
}

variable "override_body_contains" {
  description = "Optional override: text the HTTP response body must contain (1..100 characters from A-Za-z0-9 ._,:;!?@#%&+/~-)."
  type        = string
  default     = null

  validation {
    condition     = var.override_body_contains == null ? true : can(regex("^[A-Za-z0-9 ._,:;!?@#%&+/~-]{1,100}$", var.override_body_contains))
    error_message = "override_body_contains must be 1..100 characters from A-Za-z0-9 ._,:;!?@#%&+/~- (no quotes, newlines, brackets, $ or comparison operators)."
  }
}

variable "override_dns_resolver" {
  description = "Optional override: public DNS resolver for the DNS check, one of 1.1.1.1:53, 1.0.0.1:53, 8.8.8.8:53, 8.8.4.4:53, 9.9.9.9:53, 149.112.112.112:53, 208.67.222.222:53, 208.67.220.220:53."
  type        = string
  default     = null

  validation {
    condition = var.override_dns_resolver == null ? true : contains(
      ["1.1.1.1:53", "1.0.0.1:53", "8.8.8.8:53", "8.8.4.4:53", "9.9.9.9:53", "149.112.112.112:53", "208.67.222.222:53", "208.67.220.220:53"],
      var.override_dns_resolver
    )
    error_message = "override_dns_resolver must be one of the allowed public resolvers (for example 1.1.1.1:53)."
  }
}

variable "tags" {
  description = "Tags set on the S3 object. Needs s3:PutObjectTagging; leave empty to avoid it on create."
  type        = map(string)
  default     = {}
  nullable    = false
}
