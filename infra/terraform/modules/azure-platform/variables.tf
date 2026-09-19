variable "name_prefix" {
  description = "Prefix applied to all resource names, e.g. poetic-musings-dev."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)."
  type        = string
}

variable "location" {
  description = "Azure region for platform resources."
  type        = string
}

variable "tags" {
  description = "Common tags applied to every resource for cost allocation and ownership tracking."
  type        = map(string)
}
