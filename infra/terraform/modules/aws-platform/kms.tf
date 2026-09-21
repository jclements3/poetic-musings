data "aws_region" "current" {}

# CloudWatch Logs needs an explicit grant in the key policy to use a
# customer-managed KMS key for log group encryption -- it is not covered
# by the default "account root has full access" statement alone, since
# logs.amazonaws.com is a different principal. Scoped to log groups in
# this account/region via the aws:SourceArn condition.
data "aws_iam_policy_document" "platform_key" {
  statement {
    sid    = "AccountRootFullAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_key" "platform" {
  description             = "CMK for ${var.name_prefix} platform resources (ECR images, S3 artifacts)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.platform_key.json

  tags = var.tags
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${var.name_prefix}-platform"
  target_key_id = aws_kms_key.platform.key_id
}
