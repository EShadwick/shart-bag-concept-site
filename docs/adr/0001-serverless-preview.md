# ADR 0001: Serverless preview instead of a container host

**Status:** Accepted
**Date:** 2026-10-09

## Context

The client wants reviewers to see the concept for short periods, and does not want a running monthly bill. The client must be able to switch the preview on and off without help.

Options considered:

1. **Containers on ECS Fargate behind a load balancer.** Mirrors the local Docker setup closely. The load balancer and tasks bill by the hour while the preview exists, so forgetting to tear it down costs money every day.
2. **A single EC2 or Lightsail instance.** Simple, but billed by the hour and needs patching.
3. **S3 + CloudFront for the site, Lambda + DynamoDB for feedback.** Every piece bills per request or per GB stored. An idle preview costs effectively nothing.

## Decision

Option 3. The site is static, and the only dynamic feature is a form that writes one row. That workload fits request-priced services exactly.

Docker is still used where it adds value: the local environment and the CI smoke test (ADR 0004).

## Consequences

- Idle cost is close to zero, and teardown removes everything except a few KB of Terraform state.
- The API is written against the Lambda event shape, so local development needs a small adapter (`local-server.js`).
- A new CloudFront distribution takes a few minutes to propagate, so "Deploy preview" is not instant.
- If the project later needs server-side rendering or long-running work, revisit containers.
- Revisited in ADR 0005: the client later asked for a link that never changes, so an EC2 server option was added alongside the preview. The preview remains the zero-cost choice.
