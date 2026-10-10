#!/usr/bin/env bash
# Creates the project labels and backlog issues from docs/backlog.md.
# Run once from the repo root after the first push:  bash scripts/seed-issues.sh
# Requires the GitHub CLI (gh) logged in to the account that owns the repo.
set -euo pipefail

label() { gh label create "$1" --color "$2" --description "$3" --force >/dev/null; }
label site           "f283aa" "Concept site content and layout"
label api            "7fd0f0" "Feedback API"
label infra          "22252a" "Terraform and AWS"
label devops         "ffd23f" "CI, workflows, local environment"
label docs           "d9c39a" "Brief, architecture, runbook"
label client-request "b3261e" "Raised by the client"
label blocked        "6b5a45" "Waiting on something outside the team"
label future         "cfcac1" "Not in this phase"

issue() { # title, labels, body, state
  local url
  url=$(gh issue create --title "$1" --label "$2" --body "$3")
  if [ "${4:-open}" = "closed" ]; then gh issue close "$url" --reason completed >/dev/null; fi
  echo "$url  $1"
}

issue "Client brief and acceptance criteria" "docs" "Capture goals, scope, out of scope and acceptance criteria in docs/client-brief.md." closed
issue "Concept site: bags, charms, kit, clips, film" "site" "One-page concept site with the three bags, Shart Force charms, kit contents, field-test clips and the Operation White Pants short." closed
issue "Feedback form and API" "api" "Form on the site, Lambda-shaped handler with validation, honeypot, size limit and unit tests." closed
issue "Local environment with Docker Compose" "devops" "nginx + API + DynamoDB Local so the full site, including feedback, runs with one command." closed
issue "CI pipeline" "devops" "API unit tests, site asset check, terraform fmt/validate and a Compose smoke test on every PR." closed
issue "AWS bootstrap" "infra" "State bucket, GitHub OIDC deploy role scoped to the preview environment, monthly budget alert." closed
issue "Preview environment" "infra" "S3 + CloudFront with a password gate, Lambda function URL behind OAC, DynamoDB with TTL." closed
issue "Deploy, tear down and export workflows" "devops" "Manual workflows to create the preview, export feedback to CSV, and delete everything." closed
issue "Server option: EC2 with a fixed address" "infra,devops,client-request" "t4g.micro behind CloudFront with an Elastic IP, origin locked to CloudFront, deploys over SSM, start/stop/nightly stop workflows. See ADR 0005." closed
issue "Replace or crop the golf field-test clip" "site,client-request" "Real golf brand logos are visible on the cart bag. Regenerate the clip or crop them out before wider sharing."
issue "Accessibility pass" "site" "Keyboard-only and screen reader walkthrough of the site and the feedback form."
issue "Add pricing" "site,blocked" "Waiting on the maker's quote."
issue "Custom domain for the preview" "infra,future" "Route 53 or external DNS plus an ACM certificate in us-east-1 for CloudFront."
issue "Shart Force Films: missions 2 to 4" "site,future" "First Date, Job Interview and Long Drive."
issue "Friendly offline page for the stopped server" "infra" "While the server is stopped, CloudFront shows its own error page. Serve a short 'review is paused' page instead (origin failover to a small S3 bucket)."
issue "OS patching for the server" "infra,devops" "Patch Amazon Linux on a schedule with Systems Manager Patch Manager, or rebuild the instance from the latest image."
