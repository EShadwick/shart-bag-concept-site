# The client preview environment. Created by the "Deploy preview" workflow and
# deleted by "Tear down preview". Nothing here is billed by the hour.
#
#   Browser --HTTPS + password--> CloudFront --(OAC)--> S3      (site files)
#                                            \--(OAC)--> Lambda function URL --> DynamoDB (feedback)

terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
  # Bucket, key and region are passed by the workflow with -backend-config.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = "shart-bag-concept-site"
      ManagedBy = "terraform"
      Stack     = "preview"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name        = "${var.name_prefix}-preview"
  site_bucket = "${local.name}-site-${data.aws_caller_identity.current.account_id}"
  fn_name     = "${local.name}-feedback"
  credentials = base64encode("${var.preview_username}:${var.preview_password}")
}

# ---------- Site files (S3, private) ----------

resource "aws_s3_bucket" "site" {
  bucket        = local.site_bucket
  force_destroy = true # tear down deletes the uploaded files too
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "site" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.preview.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket     = aws_s3_bucket.site.id
  policy     = data.aws_iam_policy_document.site.json
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# ---------- Feedback storage (DynamoDB, on-demand) ----------

resource "aws_dynamodb_table" "feedback" {
  name         = "${local.name}-feedback"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }
}

# ---------- Feedback API (Lambda + function URL) ----------

data "archive_file" "api" {
  type        = "zip"
  source_dir  = "${path.module}/../../api"
  output_path = "${path.module}/.build/feedback-api.zip"
  excludes    = ["test", "Dockerfile", ".dockerignore", "src/local-server.js"]
}

data "aws_iam_policy_document" "fn_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fn" {
  name               = "${local.fn_name}-fn"
  assume_role_policy = data.aws_iam_policy_document.fn_trust.json
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${local.fn_name}"
  retention_in_days = 7
}

data "aws_iam_policy_document" "fn" {
  statement {
    sid       = "WriteFeedback"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.feedback.arn]
  }
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.fn.arn}:*"]
  }
}

resource "aws_iam_role_policy" "fn" {
  name   = "feedback-fn"
  role   = aws_iam_role.fn.id
  policy = data.aws_iam_policy_document.fn.json
}

resource "aws_lambda_function" "feedback" {
  function_name    = local.fn_name
  description      = "Stores client feedback for the Shart Bag concept preview"
  role             = aws_iam_role.fn.arn
  runtime          = "nodejs24.x"
  architectures    = ["arm64"]
  handler          = "src/handler.handler"
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  memory_size      = 128
  timeout          = 5

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.feedback.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.fn, aws_iam_role_policy.fn]
}

resource "aws_lambda_function_url" "feedback" {
  function_name      = aws_lambda_function.feedback.function_name
  authorization_type = "AWS_IAM" # only CloudFront (via OAC) can call it
}

# CloudFront docs list both permissions for an OAC-protected function URL.
resource "aws_lambda_permission" "cloudfront_url" {
  statement_id           = "AllowCloudFrontInvokeFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.feedback.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.preview.arn
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "cloudfront_invoke" {
  statement_id  = "AllowCloudFrontInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.feedback.function_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.preview.arn
}

# ---------- Edge: password gate + CDN ----------

resource "aws_cloudfront_function" "password" {
  name    = "${local.name}-password"
  runtime = "cloudfront-js-2.0"
  comment = "HTTP Basic auth gate for the concept preview"
  publish = true
  code    = templatefile("${path.module}/password-gate.js.tftpl", { credentials = local.credentials })
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${local.name}-s3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_control" "lambda" {
  name                              = "${local.name}-lambda"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "preview" {
  enabled             = true
  comment             = "Shart Bag concept preview"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  http_version        = "http2and3"

  origin {
    origin_id                = "site"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  origin {
    origin_id                = "api"
    domain_name              = regex("^https://([^/]+)/?$", aws_lambda_function_url.feedback.function_url)[0]
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda.id
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "site"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.password.arn
    }
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "api"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    compress                 = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.password.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
