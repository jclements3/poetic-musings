locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  }

  name_prefix = "${var.project_name}-${var.environment}"
}

module "aws_platform" {
  source = "./modules/aws-platform"

  name_prefix       = local.name_prefix
  environment       = var.environment
  tags              = local.common_tags
  ci_principal_arn  = var.ci_principal_arn
}

module "azure_platform" {
  source = "./modules/azure-platform"
  count  = var.enable_azure ? 1 : 0

  name_prefix = local.name_prefix
  environment = var.environment
  location    = var.azure_location
  tags        = local.common_tags
}
