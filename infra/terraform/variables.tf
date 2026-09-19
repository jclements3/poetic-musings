variable "environment" {
  description = "Deployment environment name (dev, prod, etc). Used for naming and tagging."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Short project identifier used as a naming prefix across resources."
  type        = string
  default     = "poetic-musings"
}

variable "owner" {
  description = "Owning team/individual, applied as a tag for cost allocation and accountability."
  type        = string
  default     = "platform-team"
}

variable "aws_region" {
  description = "Primary AWS region for the platform resources."
  type        = string
  default     = "us-east-1"
}

variable "azure_location" {
  description = "Primary Azure region for the platform resources."
  type        = string
  default     = "eastus"
}

variable "enable_azure" {
  description = "Whether to provision the Azure platform module. Allows AWS-only plans in environments without an Azure subscription configured."
  type        = bool
  default     = true
}

variable "ci_principal_arn" {
  description = "ARN of the CI identity (e.g. OIDC role or user) that should be trusted to assume the AWS ECR-push role. Left empty disables the trust relationship's principal until supplied per-environment."
  type        = string
  default     = ""
}
