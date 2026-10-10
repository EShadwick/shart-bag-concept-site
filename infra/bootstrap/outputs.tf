output "state_bucket" {
  description = "Set as the TF_STATE_BUCKET repository variable."
  value       = aws_s3_bucket.state.bucket
}

output "deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN variable on the GitHub 'preview' environment."
  value       = aws_iam_role.deployer.arn
}

output "aws_region" {
  description = "Set as the AWS_REGION repository variable."
  value       = var.aws_region
}
