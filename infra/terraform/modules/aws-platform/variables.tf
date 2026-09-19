variable "name_prefix" {
  description = "Prefix applied to all resource names, e.g. poetic-musings-dev."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)."
  type        = string
}

variable "tags" {
  description = "Common tags applied to every resource for cost allocation and ownership tracking."
  type        = map(string)
}

variable "ci_principal_arn" {
  description = "ARN of the CI identity trusted to assume the ECR-push role. Empty string yields a role with no assumable trust principal (safe default; must be supplied to actually use the role)."
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for the platform VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 2
}
