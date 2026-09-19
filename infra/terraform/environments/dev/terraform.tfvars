# dev environment — same modules as prod, smaller/cheaper knobs.
# Usage:
#   terraform init
#   terraform plan -var-file=environments/dev/terraform.tfvars

environment    = "dev"
project_name   = "poetic-musings"
owner          = "platform-team"
aws_region     = "us-east-1"
azure_location = "eastus"

# Azure module is opt-in per environment; dev keeps it on to exercise
# both clouds, but a sandbox account without Azure access could set this
# to false and plan AWS-only.
enable_azure = true

# CI OIDC role ARN for this environment's pipeline. Left blank in this
# demo repo (see modules/aws-platform/iam.tf for the safe fallback).
ci_principal_arn = ""
