output "server_url" {
  description = "Send this link (plus the username and password) to reviewers. It stays the same across stops and starts."
  value       = "https://${aws_cloudfront_distribution.server.domain_name}/"
}

output "instance_id" {
  description = "The EC2 instance the start, stop and deploy workflows act on."
  value       = aws_instance.server.id
}

output "public_ip" {
  description = "The server's fixed Elastic IP. Only CloudFront can connect to it."
  value       = aws_eip.server.public_ip
}

output "feedback_table" {
  description = "DynamoDB table that stores feedback from the server."
  value       = aws_dynamodb_table.feedback.name
}
