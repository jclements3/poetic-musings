############################################
# Remote state backend
#
# Primary: AWS S3 + DynamoDB for state locking.
# This is a stub for a training/demo repo — the bucket/table below are
# NOT created by this configuration (chicken-and-egg problem with remote
# state) and must be provisioned once, out of band, e.g.:
#
#   aws s3api create-bucket --bucket poetic-musings-tfstate --region us-east-1
#   aws s3api put-bucket-versioning --bucket poetic-musings-tfstate \
#       --versioning-configuration Status=Enabled
#   aws s3api put-bucket-encryption --bucket poetic-musings-tfstate \
#       --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
#   aws dynamodb create-table --table-name poetic-musings-tflock \
#       --attribute-definitions AttributeName=LockID,AttributeType=S \
#       --key-schema AttributeName=LockID,KeyType=HASH \
#       --billing-mode PAY_PER_REQUEST
#
# Alternative (Azure): use azurerm backend against a Storage Account with
# a private container and Azure AD-based access instead of shared keys,
# e.g.:
#
#   terraform {
#     backend "azurerm" {
#       resource_group_name  = "rg-poetic-musings-state"
#       storage_account_name = "poeticmusingstate"
#       container_name       = "tfstate"
#       key                  = "poetic-musings.tfstate"
#       use_azuread_auth     = true
#     }
#   }
#
# This repo is a portfolio/demo — `terraform init` here will use local
# state unless the S3 backend below is uncommented and the bucket/table
# already exist. Left commented so `terraform validate` works with no
# cloud credentials or pre-existing infrastructure.
############################################

# terraform {
#   backend "s3" {
#     bucket         = "poetic-musings-tfstate"
#     key            = "poetic-musings/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "poetic-musings-tflock"
#     encrypt        = true
#   }
# }
