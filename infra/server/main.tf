# The "server" option: one small EC2 instance runs the same Docker Compose app as a laptop,
# behind CloudFront for HTTPS and the password gate. The address never changes; start and
# stop the instance with the "Server: start" and "Server: stop" workflows. It also stops
# itself every night so it cannot be forgotten.
#
#   Browser --HTTPS + password--> CloudFront --HTTP + origin secret--> Elastic IP --> EC2
#                                                                      nginx -> API container -> DynamoDB
#
# Billed while this stack exists: the Elastic IP (about $3.65/month) and an 8 GB disk (about $0.64/month).
# Billed only while the instance runs: t4g.micro (about $0.0084/hour).

terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
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
      Stack     = "server"
    }
  }
}

data "aws_partition" "current" {}

locals {
  name                = "${var.name_prefix}-server"
  credentials         = base64encode("${var.preview_username}:${var.preview_password}")
  origin_secret_param = "/${var.name_prefix}/server/origin-secret"
  origin_header       = "X-Origin-Verify"
}

# ---------- Network: its own small VPC, one public subnet, no NAT gateway ----------

# Pick a regular Availability Zone (not a Local Zone) that offers the instance type.
data "aws_availability_zones" "regular" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_ec2_instance_type_offerings" "zones" {
  location_type = "availability-zone"
  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

locals {
  zone = sort(setintersection(data.aws_availability_zones.regular.names, data.aws_ec2_instance_type_offerings.zones.locations))[0]
}

resource "aws_vpc" "server" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = local.name }
}

resource "aws_internet_gateway" "server" {
  vpc_id = aws_vpc.server.id
  tags   = { Name = local.name }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.server.id
  cidr_block        = "10.42.1.0/24"
  availability_zone = local.zone
  tags              = { Name = "${local.name}-public" }

  lifecycle {
    # If AWS later offers the instance type in another zone, keep the existing subnet and server.
    ignore_changes = [availability_zone]
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.server.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.server.id
  }
  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Only CloudFront can reach the server, and only on port 80. There is no SSH port:
# administration goes through AWS Systems Manager.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "server" {
  name        = "${local.name}-web"
  description = "HTTP from CloudFront only"
  vpc_id      = aws_vpc.server.id
  tags        = { Name = "${local.name}-web" }
}

resource "aws_vpc_security_group_ingress_rule" "from_cloudfront" {
  security_group_id = aws_security_group.server.id
  description       = "HTTP from CloudFront edge locations"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.server.id
  description       = "OS packages, container images, GitHub, DynamoDB and Systems Manager"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------- Fixed address ----------

# The network interface and its Elastic IP exist before the instance, so the server has
# its permanent public address (and internet access) from the first second of first boot.
resource "aws_network_interface" "server" {
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.server.id]
  tags            = { Name = local.name }
}

resource "aws_eip" "server" {
  domain            = "vpc"
  network_interface = aws_network_interface.server.id
  tags              = { Name = local.name }

  depends_on = [aws_internet_gateway.server]
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

# ---------- Origin secret ----------

# CloudFront adds this header to every request it sends to the server, and nginx refuses
# any request without it. That stops anyone (including another CloudFront distribution)
# from skipping the password gate by going to the server's address directly.
resource "random_password" "origin_secret" {
  length  = 40
  special = false
}

resource "aws_ssm_parameter" "origin_secret" {
  name        = local.origin_secret_param
  description = "Header value CloudFront sends to the Shart Bag server; nginx rejects requests without it"
  type        = "SecureString"
  value       = random_password.origin_secret.result
}

# ---------- Identity for the instance ----------

data "aws_iam_policy_document" "instance_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${local.name}-instance"
  description        = "Shart Bag server: Systems Manager access, save feedback, read the origin secret"
  assume_role_policy = data.aws_iam_policy_document.instance_trust.json
}

# Lets the "Server: create or update" workflow run deploy commands without SSH.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "instance" {
  statement {
    sid       = "SaveFeedback"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.feedback.arn]
  }
  statement {
    sid       = "ReadOriginSecret"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.origin_secret.arn]
  }
}

resource "aws_iam_role_policy" "instance" {
  name   = "server-app"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${local.name}-instance"
  role = aws_iam_role.instance.name
}

# ---------- The server ----------

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${var.architecture}"
}

resource "aws_instance" "server" {
  ami                  = data.aws_ssm_parameter.al2023.insecure_value
  instance_type        = var.instance_type
  iam_instance_profile = aws_iam_instance_profile.instance.name

  # A shutdown from inside the server (the nightly backstop timer) stops it; it is never terminated.
  instance_initiated_shutdown_behavior = "stop"

  primary_network_interface {
    network_interface_id = aws_network_interface.server.id
  }

  # First boot only: clone the repo, install Docker, start the app (see deploy/server/).
  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    repo_url            = var.repo_url
    table_name          = aws_dynamodb_table.feedback.name
    origin_secret_param = aws_ssm_parameter.origin_secret.name
  })

  # IMDSv2 only. Hop limit 2 lets the API container reach the instance role credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # "standard" means the instance slows down instead of billing for extra CPU.
  credit_specification {
    cpu_credits = "standard"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
    tags        = { Name = local.name }
  }

  tags = { Name = local.name }

  lifecycle {
    # A newer Amazon Linux image or an edited first-boot script should not replace a
    # running server. Code updates go through deploy/server/deploy.sh instead.
    ignore_changes = [ami, user_data]
  }

  # Internet access and permissions must exist before first boot runs.
  depends_on = [
    aws_eip.server,
    aws_route_table_association.public,
    aws_vpc_security_group_egress_rule.all,
    aws_iam_role_policy.instance,
    aws_iam_role_policy_attachment.ssm_core,
  ]
}

# ---------- Edge: HTTPS, password gate, origin secret ----------

resource "aws_cloudfront_function" "password" {
  name    = "${local.name}-password"
  runtime = "cloudfront-js-2.0"
  comment = "HTTP Basic auth gate for the concept server"
  publish = true
  code    = templatefile("${path.module}/../preview/password-gate.js.tftpl", { credentials = local.credentials })
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

resource "aws_cloudfront_distribution" "server" {
  enabled      = true
  comment      = "Shart Bag concept server"
  price_class  = "PriceClass_100"
  http_version = "http2and3"

  origin {
    origin_id   = "server"
    domain_name = aws_eip.server.public_dns
    # Fail fast with an error page while the server is stopped instead of hanging.
    connection_attempts = 1
    connection_timeout  = 5

    custom_header {
      name  = local.origin_header
      value = random_password.origin_secret.result
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # No caching: what reviewers see is always what the server is running right now.
  # No origin request policy, and the password function deletes the Authorization header,
  # so the reviewer password never travels on the HTTP leg to the server.
  default_cache_behavior {
    target_origin_id       = "server"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.disabled.id
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.password.arn
    }
  }

  # Do not remember "server is stopped" errors after it starts again.
  dynamic "custom_error_response" {
    for_each = [502, 503, 504]
    content {
      error_code            = custom_error_response.value
      error_caching_min_ttl = 0
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
