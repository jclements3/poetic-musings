output "aws_ecr_repository_url" {
  description = "URL of the ECR repository for container image pushes."
  value       = module.aws_platform.ecr_repository_url
}

output "aws_artifacts_bucket_name" {
  description = "Name of the S3 bucket used for build/release artifacts."
  value       = module.aws_platform.artifacts_bucket_name
}

output "aws_ci_role_arn" {
  description = "ARN of the least-privilege IAM role CI assumes to push images/artifacts."
  value       = module.aws_platform.ci_role_arn
}

output "azure_container_registry_login_server" {
  description = "Login server for the Azure Container Registry (null if Azure module disabled)."
  value       = var.enable_azure ? module.azure_platform[0].acr_login_server : null
}

output "azure_resource_group_name" {
  description = "Name of the Azure resource group holding the platform resources (null if Azure module disabled)."
  value       = var.enable_azure ? module.azure_platform[0].resource_group_name : null
}
