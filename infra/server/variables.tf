variable "aws_region" {
  description = "Region for the server, its network and the feedback table. Must match the bootstrap stack."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Must match the bootstrap stack so the deploy role is allowed to manage these resources."
  type        = string
  default     = "shart-bag"
}

variable "repo_url" {
  description = "Public HTTPS clone URL of this repository. The server pulls the app from here."
  type        = string

  validation {
    condition     = can(regex("^https://", var.repo_url))
    error_message = "repo_url must be an https:// clone URL."
  }
}

variable "instance_type" {
  description = "EC2 instance type. The deploy role only allows these two."
  type        = string
  default     = "t4g.micro"

  validation {
    condition     = contains(["t4g.micro", "t4g.small"], var.instance_type)
    error_message = "Use t4g.micro or t4g.small."
  }
}

variable "architecture" {
  description = "CPU architecture of the Amazon Linux 2023 image. t4g instances are arm64."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "Use arm64 or x86_64."
  }
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
