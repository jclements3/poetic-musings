output "vpc_id" {
  description = "ID of the platform VPC."
  value       = aws_vpc.platform.id
}

output "ecr_repository_url" {
  description = "Repository URL for pushing/pulling container images."
  value       = aws_ecr_repository.images.repository_url
}

output "artifacts_bucket_name" {
  description = "Name of the encrypted, versioned S3 artifacts bucket."
  value       = aws_s3_bucket.artifacts.id
}

output "ci_role_arn" {
  description = "ARN of the least-privilege IAM role CI assumes to push images/artifacts."
  value       = aws_iam_role.ci_push.arn
}
