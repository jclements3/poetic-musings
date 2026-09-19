resource "aws_kms_key" "platform" {
  description             = "CMK for ${var.name_prefix} platform resources (ECR images, S3 artifacts)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = var.tags
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${var.name_prefix}-platform"
  target_key_id = aws_kms_key.platform.key_id
}
