# prod environment — same modules as dev, reused via the same root config.
# Usage:
#   terraform init
#   terraform plan -var-file=environments/prod/terraform.tfvars

environment    = "prod"
project_name   = "poetic-musings"
owner          = "platform-team"
aws_region     = "us-east-1"
azure_location = "eastus"

enable_azure = true

# Prod CI role ARN must be supplied via a secure variable source (e.g.
# TF_VAR_ci_principal_arn from a CI secret store), never committed here.
ci_principal_arn = ""
