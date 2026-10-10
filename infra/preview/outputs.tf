output "preview_url" {
  description = "Send this link (plus the username and password) to reviewers."
  value       = "https://${aws_cloudfront_distribution.preview.domain_name}/"
}

output "site_bucket" {
  value = aws_s3_bucket.site.bucket
}

output "distribution_id" {
  value = aws_cloudfront_distribution.preview.id
}

output "feedback_table" {
  value = aws_dynamodb_table.feedback.name
}

output "feedback_function" {
  value = aws_lambda_function.feedback.function_name
}
