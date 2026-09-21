# infra/terraform — Internal Developer Platform (IDP) demo

A portfolio-quality, multi-cloud Terraform layer that stands in for
provisioning a small "Internal Developer Platform" environment across AWS
and Azure, for `poetic-musings`.

**Status: the AWS side has been applied for real**, against a personal
free-tier AWS account, verified against the live API, and torn down with
`terraform destroy` afterward — see "Validation" below for exactly what
that proved, what it cost, and one real bug it caught. The Azure side
remains written-and-validated-only (no Azure subscription available at
the time).

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

`terraform validate`, `tfsec` (via the CI pipeline, on every push — see
`.github/workflows/security.yml`), and a real `terraform apply` have all
run against this code:

- **`terraform validate`** passes clean.
- **`tfsec`** passes with one documented exclusion
  (`aws-iam-no-policy-wildcards`, for object/stream-scoped ARN suffixes
  that AWS object-level permissions require — see the inline comments in
  `modules/aws-platform/iam.tf` and `network.tf`).
- **A real `terraform apply`** ran against a personal free-tier AWS
  account (`us-east-2`), AWS-only (the Azure module requires a live Azure
  subscription this account doesn't have — `terraform init` couldn't even
  configure the `azurerm` provider without one, since it authenticates on
  `configure` regardless of whether `enable_azure` leaves it with zero
  resources; that's a real limitation worth knowing, not something
  `-var enable_azure=false` alone works around). All 33 planned AWS
  resources were created successfully, verified for real via `aws ecr
  describe-repositories`, `aws ec2 describe-vpcs`, `aws s3api
  list-buckets`, and `aws kms describe-key`, then torn down with
  `terraform destroy`.
- **One real bug caught by the apply, not by `tfsec` or `validate`:**
  `aws_cloudwatch_log_group.vpc_flow_logs` failed to create with
  `AccessDeniedException: The specified KMS key does not exist or is not
  allowed to be used` — the KMS key had no policy statement granting
  `logs.<region>.amazonaws.com` permission to encrypt with it.
  CloudWatch Logs needs an *explicit* grant for a customer-managed key;
  it isn't covered by the default "account root has full access"
  statement, because the logs service is a different principal. Fixed in
  `modules/aws-platform/kms.tf` with a scoped policy statement (see the
  inline comment there) and re-verified with a second `apply`. That's
  exactly the class of error a static scanner can't catch, because
  nothing about the HCL itself is wrong — it only fails at the API level,
  which is the whole argument for actually applying infrastructure code
  at least once rather than trusting `plan`/`validate`/`tfsec` alone.

Two smaller fixes landed alongside the real apply: an
`aws_s3_bucket_lifecycle_configuration` provider warning (missing
`filter {}`, deprecated in a future AWS provider version) on both
lifecycle rules, and the Azure `enable_https_traffic_only` →
`https_traffic_only_enabled` rename (the provider had already moved past
3.x by the time this ran).
