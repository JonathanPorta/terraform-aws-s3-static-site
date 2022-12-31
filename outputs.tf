output "hostname" {
  description = "The FQDN where this static site will be accessible. (Also becomes the bucket name.))"
  value       = var.hostname
}
output "environment" {
  description = "The environment that this static site belongs to."
  value       = var.environment
}
output "bucket_fqdn" {
  description = "The FQDN of the bucket that will serve this static site."
  value       = aws_s3_bucket_website_configuration.app_bucket_website.website_endpoint
}
output "bucket" {
  description = "The name of the bucket that will server this site."
  value       = aws_s3_bucket.app_bucket.id
}
