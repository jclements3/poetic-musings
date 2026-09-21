# Least-privilege CI role: scoped to exactly the ECR repo and S3 bucket
# this module creates, not to wildcard resources. The trust policy's
# principal is intentionally empty by default (see var.ci_principal_arn);
# a real environment supplies its CI OIDC provider/role ARN there rather
# than trusting an unbound principal.

data "aws_caller_identity" "current" {}

locals {
  # AWS does not allow an empty Principal block. When no CI principal is
  # supplied we fall back to the current account root, which grants no
  # implicit permissions on its own but keeps the policy document valid
  # for `terraform validate`/`plan` in this demo. Replace with a real
  # CI identity (e.g. GitHub OIDC role) per environment before use.
  ci_trust_principal_arns = var.ci_principal_arn != "" ? [var.ci_principal_arn] : ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
}

data "aws_iam_policy_document" "ci_assume_role" {
  statement {
    sid     = "AllowCIAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = local.ci_trust_principal_arns
    }
  }
}

resource "aws_iam_role" "ci_push" {
  name               = "${var.name_prefix}-ci-push"
  assume_role_policy = data.aws_iam_policy_document.ci_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "ci_push" {
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"] # GetAuthorizationToken is account-scoped only; AWS requires resource "*"
  }

  statement {
    sid    = "ECRPushToRepo"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.images.arn]
  }

  statement {
    sid    = "ArtifactsBucketReadWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
    ]
    # tfsec:ignore:aws-iam-no-policy-wildcards -- "/*" here is the standard
    # S3 object-path suffix scoped to this one named bucket's ARN, not an
    # account- or service-wide wildcard; S3 object-level permissions require it.
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*",
    ]
  }

  statement {
    sid    = "UseKMSKeyForEncryption"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.platform.arn]
  }
}

resource "aws_iam_role_policy" "ci_push" {
  name   = "${var.name_prefix}-ci-push"
  role   = aws_iam_role.ci_push.id
  policy = data.aws_iam_policy_document.ci_push.json
}
