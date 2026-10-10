variable "aws_region" {
  description = "Region for S3, Lambda and DynamoDB. Must match the bootstrap stack."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Must match the bootstrap stack so the deploy role is allowed to manage these resources."
  type        = string
  default     = "shart-bag"
}

variable "preview_username" {
  description = "Username reviewers type at the password prompt."
  type        = string
  default     = "client"
}

variable "preview_password" {
  description = "Shared password for reviewers. Comes from the PREVIEW_PASSWORD GitHub secret."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.preview_password) >= 12
    error_message = "Use a preview password of at least 12 characters."
  }
}
