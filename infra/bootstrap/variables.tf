variable "aws_region" {
  description = "Region for the state bucket, deploy role scope and preview resources."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every resource name. The deploy role can only touch resources that start with <prefix>-preview-."
  type        = string
  default     = "shart-bag"
}

variable "github_owner" {
  description = "GitHub user or org that owns the repo."
  type        = string
}

variable "github_repo" {
  description = "Repository name."
  type        = string
  default     = "shart-bag-concept-site"
}

variable "state_bucket_name" {
  description = "Override the state bucket name. Leave null to use <prefix>-tfstate-<account id>."
  type        = string
  default     = null
}

variable "create_github_oidc_provider" {
  description = "Set false if this AWS account already has the token.actions.githubusercontent.com OIDC provider."
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address that receives budget alerts."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly budget. You get an email at 20 percent actual spend and when the forecast passes 100 percent."
  type        = string
  default     = "5"
}
