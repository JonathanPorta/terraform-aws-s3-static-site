# terraform-aws-s3-static-site

Very simple Terraform module for deploying a static site into an S3 bucket.

## Module Documentation

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                   | Version  |
| ------------------------------------------------------ | -------- |
| <a name="requirement_aws"></a> [aws](#requirement_aws) | ~> 4.8.0 |

## Providers

| Name                                             | Version  |
| ------------------------------------------------ | -------- |
| <a name="provider_aws"></a> [aws](#provider_aws) | ~> 4.8.0 |

## Modules

No modules.

## Resources

| Name                                                                                                                                                                  | Type        |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| [aws_s3_bucket.app_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket)                                                     | resource    |
| [aws_s3_bucket_acl.app_bucket_acl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_acl)                                         | resource    |
| [aws_s3_bucket_policy.app_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy)                                | resource    |
| [aws_s3_bucket_versioning.app_bucket_versioning](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning)                    | resource    |
| [aws_s3_bucket_website_configuration.app_bucket_website](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_website_configuration) | resource    |
| [aws_s3_object.app_bucket_source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object)                                              | resource    |
| [aws_iam_policy_document.app_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document)                       | data source |

## Inputs

| Name                                                                  | Description                                                                              | Type     | Default | Required |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | -------- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input_environment)    | The name of the environment that this static site belongs to. e.g. [staging, production] | `string` | n/a     |   yes    |
| <a name="input_hostname"></a> [hostname](#input_hostname)             | The FQDN where this static site will be accessible.                                      | `string` | n/a     |   yes    |
| <a name="input_source_files"></a> [source_files](#input_source_files) | A path to the website's source files. These will be uploaded to the bucket.              | `string` | n/a     |   yes    |

## Outputs

| Name                                                                 | Description                                              |
| -------------------------------------------------------------------- | -------------------------------------------------------- |
| <a name="output_bucket"></a> [bucket](#output_bucket)                | The name of the bucket that will server this site.       |
| <a name="output_bucket_fqdn"></a> [bucket_fqdn](#output_bucket_fqdn) | The FQDN of the bucket that will serve this static site. |
| <a name="output_environment"></a> [environment](#output_environment) | The domain to which the redirect will point.             |
| <a name="output_hostname"></a> [hostname](#output_hostname)          | The domain that will serve a redirect.                   |

<!-- END_TF_DOCS -->
