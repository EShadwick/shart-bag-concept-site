# One-time setup, run from your own machine with admin credentials.
# Creates the things that must exist before GitHub Actions can deploy:
#   1. an S3 bucket for Terraform state (the preview stack's memory)
#   2. a GitHub OIDC trust so Actions can assume a role without stored AWS keys
#   3. a deploy role scoped to this repo's "preview" environment
#   4. a monthly budget that emails you before costs become a surprise
#
# This stack stays in place when the preview is torn down. It costs nothing to keep
# except a few KB of state storage.

terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.tags
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  prefix     = var.name_prefix
  repo_full  = "${var.github_owner}/${var.github_repo}"
  # OIDC subject prefix GitHub puts in this repo's tokens (see variables.tf).
  github_subject = var.github_repo_id == null ? "repo:${local.repo_full}" : "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"
  state_bkt      = coalesce(var.state_bucket_name, "${local.prefix}-tfstate-${local.account_id}")
  tags = {
    Project   = "shart-bag-concept-site"
    ManagedBy = "terraform"
    Stack     = "bootstrap"
  }
}

# ---------- Terraform state bucket ----------

resource "aws_s3_bucket" "state" {
  bucket = local.state_bkt
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ---------- GitHub Actions OIDC ----------

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only jobs that run in this repo's "preview" GitHub environment can assume the role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_subject}:environment:preview"]
    }
  }
}

resource "aws_iam_role" "deployer" {
  name                 = "${local.prefix}-preview-deployer"
  description          = "Assumed by GitHub Actions to deploy and tear down the Shart Bag concept preview"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deployer" {
  statement {
    sid       = "TerraformState"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    sid       = "TerraformStateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/preview/*"]
  }

  statement {
    sid       = "SiteBucket"
    actions   = ["s3:*"]
    resources = ["arn:${local.partition}:s3:::${local.prefix}-preview-*", "arn:${local.partition}:s3:::${local.prefix}-preview-*/*"]
  }

  statement {
    sid       = "FeedbackTable"
    actions   = ["dynamodb:*"]
    resources = ["arn:${local.partition}:dynamodb:${var.aws_region}:${local.account_id}:table/${local.prefix}-preview-*"]
  }

  statement {
    sid       = "FeedbackFunction"
    actions   = ["lambda:*"]
    resources = ["arn:${local.partition}:lambda:${var.aws_region}:${local.account_id}:function:${local.prefix}-preview-*"]
  }

  statement {
    sid = "FunctionRole"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole", "iam:TagRole", "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/${local.prefix}-preview-*"]
  }
  statement {
    sid       = "PassFunctionRoleToLambda"
    actions   = ["iam:PassRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/${local.prefix}-preview-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  statement {
    sid       = "FunctionLogs"
    actions   = ["logs:*"]
    resources = ["arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${local.prefix}-preview-*"]
  }
  statement {
    sid       = "DescribeLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  # CloudFront does not support resource-level scoping for most create/list calls.
  # Documented trade-off: see docs/adr/0003-terraform-and-github-oidc.md.
  statement {
    sid       = "CloudFront"
    actions   = ["cloudfront:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deployer" {
  name   = "deploy-preview"
  role   = aws_iam_role.deployer.id
  policy = data.aws_iam_policy_document.deployer.json
}

# ---------- Cost guardrail ----------

resource "aws_budgets_budget" "monthly" {
  name         = "${local.prefix}-monthly"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 20
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
