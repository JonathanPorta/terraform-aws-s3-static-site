output "hostname" {
  description = "The domain that will serve a redirect."
  value       = var.hostname
}
output "environment" {
  description = "The domain to which the redirect will point."
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
