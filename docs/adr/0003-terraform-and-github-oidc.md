# ADR 0003: Terraform, split into bootstrap and preview, deployed through GitHub OIDC

**Status:** Accepted
**Date:** 2026-10-09

## Context

The preview must be created and destroyed repeatedly and identically, without the AWS console, and without storing long-lived AWS keys in GitHub.

## Decision

- **Terraform** describes all AWS resources.
- Two stacks:
  - `infra/bootstrap` is applied once, by a person, with admin credentials. It creates the Terraform state bucket, the GitHub OIDC trust, the deploy role and the budget alert. It is never torn down by automation.
  - `infra/preview` is applied and destroyed by GitHub Actions. It holds everything a reviewer touches.
- **GitHub OIDC**: workflows request a short-lived token, and AWS lets them assume the deploy role only when the token's subject is `repo:<owner>@<owner id>/<repo>@<repo id>:environment:preview`.
  - That is GitHub's immutable subject format, the default for repositories created after 2026-07-15.
  - The numeric IDs do not change when a repo is renamed, and nobody who later registers the same owner or repo name gets them, so a look-alike repo cannot assume the role.
  - Leaving `github_owner_id` and `github_repo_id` unset falls back to the older `repo:<owner>/<repo>` format for older repositories.
- **State** lives in S3 with versioning, encryption and native S3 locking (`use_lockfile`), so no DynamoDB lock table is needed.

## Least privilege, and where it stops

The deploy role can only manage S3 buckets, Lambda functions, IAM roles, log groups and DynamoDB tables whose names start with `shart-bag-preview-`. `iam:PassRole` is limited to passing those roles to Lambda.

CloudFront is the exception: distributions, functions and origin access controls get their IDs only when they are created, and several CloudFront list and create calls cannot be scoped to a resource, so the role has `cloudfront:*` on the account. That is acceptable for a personal account that hosts only this preview. In a shared account, give the preview its own AWS account under an organization.

## Consequences

- A fork or another repository cannot deploy into the account; neither can a workflow that does not declare `environment: preview`.
- GitHub environment protection rules (required reviewers, branch restrictions) can be added to `preview` to require approval before any deploy or teardown.
- The bootstrap stack must be applied before the first deploy, and its outputs copied into GitHub settings (see the runbook).

## Revision 2026-10-09

The first deploy failed at "Configure AWS credentials" with `Not authorized to perform sts:AssumeRoleWithWebIdentity`. The trust policy expected the older subject format, but this repository was created after GitHub switched new repositories to immutable subjects. Fix: the bootstrap now takes the owner and repo IDs, builds the immutable subject from them, and prints it as the `github_oidc_subject` output so it can be compared against the `sub` in CloudTrail.
