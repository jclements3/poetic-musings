# infra/terraform — Internal Developer Platform (IDP) demo

A portfolio-quality, multi-cloud Terraform layer that stands in for
provisioning a small "Internal Developer Platform" environment across AWS
and Azure. This is a training/demo artifact for `poetic-musings` — it is
written to be correct and idiomatic HCL but is **not intended to be
applied against real cloud accounts** (no credentials or backends are
wired up by default).

## Layout

```
infra/terraform/
├── backend.tf              # remote state stub (S3+DynamoDB primary, azurerm noted as alt)
├── providers.tf             # aws + azurerm provider requirements, pinned versions
├── variables.tf              # root-level input variables
├── outputs.tf                # root-level outputs (ECR URL, bucket name, ACR login server, ...)
├── main.tf                    # wires the two platform modules together
├── modules/
│   ├── aws-platform/          # VPC, ECR, S3 artifacts bucket, KMS, least-priv IAM role
│   └── azure-platform/        # Resource group, ACR, storage account, AD-integration notes
└── environments/
    ├── dev/terraform.tfvars   # dev-sized inputs
    └── prod/terraform.tfvars  # prod-sized inputs, same modules
```

Both `environments/*/terraform.tfvars` feed the *same* root module and
child modules — this is the standard "one module tree, many tfvars"
pattern for reusing infrastructure code across environments without
duplicating resource definitions.

## State strategy

State is intended to live remotely, not on a laptop:

- **Primary (AWS):** S3 bucket (versioned, SSE-encrypted) + DynamoDB table
  for locking. See `backend.tf` for the exact bucket/table bootstrap
  commands. The backend block itself is left **commented out** in this
  repo so `terraform init`/`validate` work without pre-existing AWS
  infrastructure or credentials.
- **Alternative (Azure):** `azurerm` backend against a private Storage
  Account container, using Azure AD auth (`use_azuread_auth = true`)
  instead of a shared account key. Documented alongside the S3 block.

## Plan / apply (if you actually had credentials)

```bash
cd infra/terraform
terraform init
terraform plan  -var-file=environments/dev/terraform.tfvars
terraform apply -var-file=environments/dev/terraform.tfvars
```

Swap `dev` for `prod` to target the other environment. Nothing here
should be applied without first uncommenting and pointing the backend at
a real, already-provisioned state bucket/table, and supplying a real
`ci_principal_arn`.

## Security choices

- **Encryption at rest everywhere:** S3 artifacts bucket and its access-log
  bucket use SSE (KMS for artifacts, AES256 for logs); the Azure storage
  account enforces `min_tls_version = TLS1_2` and disables shared-key
  auth in favor of Azure AD/RBAC; ECR images are encrypted with a
  customer-managed KMS key with automatic rotation enabled.
- **No public buckets/registries:** the S3 artifacts and log buckets both
  get a full `aws_s3_bucket_public_access_block` plus
  `BucketOwnerEnforced` ownership controls; the ACR and storage account
  both set `public_network_access_enabled = false`.
- **Least-privilege IAM:** the CI push role's policy is scoped to the
  exact ECR repository ARN and S3 bucket ARN this module creates — not
  `resource = "*"` — and the trust policy takes a real CI principal ARN
  per environment rather than trusting everything.
- **Tagging/naming standard:** every resource is tagged with
  `Project`, `Environment`, `Owner`, and `ManagedBy = terraform` via a
  shared `local.common_tags`, and named with a consistent
  `<project>-<environment>-<resource>` prefix, supporting cost
  allocation and ownership tracing.
- **Image integrity:** ECR repository uses `IMMUTABLE` tags and
  `scan_on_push` to catch known-vulnerable images before they're pulled,
  with a lifecycle policy to bound retention.

## Validation

`terraform`, `tfsec`, and `checkov` binaries were not present on this
machine at write time — CI is expected to run `terraform fmt -check`,
`terraform validate`, and a `tfsec`/`checkov` scan against this
directory (a separate workstream is wiring that into CI). The HCL here
was hand-checked for provider-version-correct attribute names (e.g.
azurerm 3.x's `enable_https_traffic_only` rather than the 4.x
`https_traffic_only_enabled`) and for internal consistency between
modules, but has not been machine-validated.
