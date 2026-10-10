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

# GitHub repositories created after 2026-07-15 put immutable IDs in the OIDC subject:
#   repo:OWNER@OWNER_ID/REPO@REPO_ID:environment:preview
# Older repositories use repo:OWNER/REPO:environment:preview. Leave both IDs null for that format.
# Get the IDs with:  gh api repos/<OWNER>/<REPO> --jq '.owner.id, .id'
variable "github_owner_id" {
  description = "Numeric GitHub ID of github_owner. Set together with github_repo_id."
  type        = string
  default     = null
  validation {
    condition     = var.github_owner_id == null || can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be the numeric ID from: gh api repos/<OWNER>/<REPO> --jq '.owner.id'"
  }
}

variable "github_repo_id" {
  description = "Numeric GitHub ID of github_repo. Set together with github_owner_id."
  type        = string
  default     = null
  validation {
    condition     = var.github_repo_id == null || can(regex("^[0-9]+$", var.github_repo_id))
    error_message = "github_repo_id must be the numeric ID from: gh api repos/<OWNER>/<REPO> --jq '.id'"
  }
  validation {
    condition     = (var.github_owner_id == null) == (var.github_repo_id == null)
    error_message = "Set github_owner_id and github_repo_id together, or leave both unset."
  }
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
