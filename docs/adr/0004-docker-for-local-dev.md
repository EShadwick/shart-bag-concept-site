# ADR 0004: Docker Compose for local development and CI

**Status:** Accepted
**Date:** 2026-10-09

## Context

Anyone working on the site should be able to run the full experience, including the feedback form, without an AWS account. CI should exercise the same stack a developer runs.

## Decision

`docker compose up` starts three containers:

- **web**: nginx serving `site/` and proxying `/api/*`, standing in for CloudFront.
- **api**: the feedback API on Node.js 24 (matching the Lambda runtime), running the same handler code through `local-server.js`.
- **dynamodb**: DynamoDB Local, in memory.

The CI workflow starts the same Compose file and round-trips a feedback submission.

## Consequences

- One command gives a working local environment; nothing to install except Docker.
- Local and AWS differ in the edge layer (nginx vs CloudFront, no password locally) and in request signing. Those paths are covered by the deploy checklist in the runbook, not by CI.
- The API image is only for local use and CI. In AWS the same source is shipped as a Lambda zip.
