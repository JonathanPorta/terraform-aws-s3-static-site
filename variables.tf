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
