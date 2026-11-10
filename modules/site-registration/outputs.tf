output "bucket" {
  description = "The registry bucket the registration is stored in."
  value       = aws_s3_object.registration.bucket
}

output "key" {
  description = "The object key of the registration document."
  value       = aws_s3_object.registration.key
}

output "document" {
  description = "The registration document as stored (decoded)."
  value       = jsondecode(local.content)
}

output "version_id" {
  description = "The S3 version id of the stored document (null when the bucket is not versioned)."
  value       = aws_s3_object.registration.version_id
}
