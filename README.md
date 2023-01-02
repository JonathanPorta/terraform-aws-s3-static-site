# terraform-aws-s3-static-site

Very simple Terraform module for deploying a static site into an S3 bucket.

## Module Documentation

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 4.8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 4.8.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_s3_bucket.app_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_acl.app_bucket_acl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_acl) | resource |
| [aws_s3_bucket_policy.app_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_versioning.app_bucket_versioning](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_website_configuration.app_bucket_website](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_website_configuration) | resource |
| [aws_s3_object.app_bucket_source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_iam_policy_document.app_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_environment"></a> [environment](#input\_environment) | The name of the environment that this static site belongs to. e.g. [staging, production] | `string` | n/a | yes |
| <a name="input_error_document_key"></a> [error\_document\_key](#input\_error\_document\_key) | The optional name of the error document to use for the bucket. | `string` | `"index.html"` | no |
| <a name="input_hostname"></a> [hostname](#input\_hostname) | The FQDN where this static site will be accessible. | `string` | n/a | yes |
| <a name="input_index_document_suffix"></a> [index\_document\_suffix](#input\_index\_document\_suffix) | The optional name of the index document to use for the bucket. | `string` | `"index.html"` | no |
| <a name="input_routing_rules"></a> [routing\_rules](#input\_routing\_rules) | An optional list of routing rules to apply to the bucket. | <pre>list(object({<br>    Condition = object({<br>      HttpErrorCodeReturnedEquals = string<br>      KeyPrefixEquals             = string<br>    })<br>    Redirect = object({<br>      HostName             = string<br>      HttpRedirectCode     = string<br>      Protocol             = string<br>      ReplaceKeyPrefixWith = string<br>      ReplaceKeyWith       = string<br>    })<br>  }))</pre> | `[]` | no |
| <a name="input_source_files"></a> [source\_files](#input\_source\_files) | A path to the website's source files. These will be uploaded to the bucket. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bucket"></a> [bucket](#output\_bucket) | The name of the bucket that will server this site. |
| <a name="output_bucket_fqdn"></a> [bucket\_fqdn](#output\_bucket\_fqdn) | The FQDN of the bucket that will serve this static site. |
| <a name="output_environment"></a> [environment](#output\_environment) | The environment that this static site belongs to. |
| <a name="output_hostname"></a> [hostname](#output\_hostname) | The FQDN where this static site will be accessible. (Also becomes the bucket name.)) |
<!-- END_TF_DOCS -->
