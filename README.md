# terraform-aws-s3-static-site

Very simple Terraform module for deploying a static site into an S3 bucket.

## Module Documentation

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 4.8.0 |
| <a name="requirement_betteruptime"></a> [betteruptime](#requirement\_betteruptime) | ~> 0.3.15 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 4.8.0 |
| <a name="provider_betteruptime"></a> [betteruptime](#provider\_betteruptime) | ~> 0.3.15 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_s3_bucket.app_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_acl.app_bucket_acl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_acl) | resource |
| [aws_s3_bucket_ownership_controls.app_bucket_acl_ownership](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_public_access_block.app_bucket_public_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_versioning.app_bucket_versioning](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_website_configuration.app_bucket_website](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_website_configuration) | resource |
| [aws_s3_object.app_bucket_source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [betteruptime_monitor.this](https://registry.terraform.io/providers/BetterStackHQ/better-uptime/latest/docs/resources/monitor) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_environment"></a> [environment](#input\_environment) | The name of the environment that this static site belongs to. e.g. [staging, production] | `string` | n/a | yes |
| <a name="input_error_document_key"></a> [error\_document\_key](#input\_error\_document\_key) | The optional name of the error document to use for the bucket. | `string` | `"index.html"` | no |
| <a name="input_hostname"></a> [hostname](#input\_hostname) | The FQDN where this static site will be accessible. | `string` | n/a | yes |
| <a name="input_index_document_suffix"></a> [index\_document\_suffix](#input\_index\_document\_suffix) | The optional name of the index document to use for the bucket. | `string` | `"index.html"` | no |
| <a name="input_monitoring"></a> [monitoring](#input\_monitoring) | Whether or not to enable monitoring. | `bool` | `false` | no |
| <a name="input_routing_rule_key_prefix_equals"></a> [routing\_rule\_key\_prefix\_equals](#input\_routing\_rule\_key\_prefix\_equals) | The optional key prefix to match. | `string` | `null` | no |
| <a name="input_routing_rule_replace_key_with"></a> [routing\_rule\_replace\_key\_with](#input\_routing\_rule\_replace\_key\_with) | The optional name key to replace with. | `string` | `null` | no |
| <a name="input_source_files"></a> [source\_files](#input\_source\_files) | A path to the website's source files. These will be uploaded to the bucket. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bucket"></a> [bucket](#output\_bucket) | The name of the bucket that will server this site. |
| <a name="output_bucket_fqdn"></a> [bucket\_fqdn](#output\_bucket\_fqdn) | The FQDN of the bucket that will serve this static site. |
| <a name="output_environment"></a> [environment](#output\_environment) | The environment that this static site belongs to. |
| <a name="output_hostname"></a> [hostname](#output\_hostname) | The FQDN where this static site will be accessible. (Also becomes the bucket name.)) |
<!-- END_TF_DOCS -->
