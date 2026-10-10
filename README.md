# Shart Bag: concept site and client preview environment

A concept website for **Shart Bag**, a novelty shark-shaped fanny pack for bathroom emergencies, plus everything needed to put it in front of a few reviewers safely and take it down again: a feedback API, a local Docker environment, CI, and an on-demand AWS preview that is built and destroyed from GitHub Actions.

> **About this project.** Shart Bag is my own product concept. I run it here as if it were a client engagement (brief, decisions, backlog, pull requests, a password-protected preview and a teardown) to show how I would deliver the same work for a paying client.

| | |
|---|---|
| **Client** | Shart Bag (novelty product, pre-launch) |
| **Engagement** | Concept website + review environment |
| **Delivered by** | Eric Shadwick |
| **Status** | Concept review. Not for sale. |

## What the client gets

- A one-page concept site: three bags, the "Shart Force" zipper charms, kit contents, field-test clips and a one-minute black-and-white short.
- A **feedback form** so reviewers can say which bag and charm they like and whether they would buy one.
- A **private preview link** behind a username and password, which exists only while a review is running.
- A **CSV of all feedback**, exported automatically when the preview is torn down.

## Architecture

```mermaid
flowchart LR
    R[Reviewer browser] -->|HTTPS + password| CF[CloudFront<br/>password gate function]
    CF -->|OAC signed| S3[(S3<br/>site files)]
    CF -->|/api/* OAC signed| L[Lambda function URL<br/>Node.js 24]
    L --> D[(DynamoDB<br/>feedback, 180-day TTL)]
    GH[GitHub Actions] -->|OIDC, no stored keys| AWS[IAM deploy role]
    AWS -->|Terraform apply / destroy| CF
```

More detail: [docs/architecture.md](docs/architecture.md). Design decisions: [docs/adr](docs/adr).

## Run it locally

Requires Docker Desktop.

```bash
docker compose up --build
# open http://localhost:8080
docker compose down
```

The local stack runs the same site and the same Lambda handler, with nginx standing in for CloudFront and DynamoDB Local standing in for DynamoDB. Nothing touches AWS.

## Preview environment (AWS)

| Action | How |
|---|---|
| Turn it on | Actions → **Deploy preview** → Run workflow. The job summary prints the link. |
| Get feedback so far | Actions → **Export feedback** → download the CSV artifact. |
| Turn it off | Actions → **Tear down preview** → type `teardown`. Feedback is exported first, then everything is deleted. |

First-time AWS and GitHub setup is a one-time job: see [docs/runbook.md](docs/runbook.md).

### Cost

Nothing in the preview is billed by the hour: S3, CloudFront, Lambda and DynamoDB on-demand all charge per request or per GB stored, which for a handful of reviewers comes to cents at most. After teardown, the only thing left in AWS is the Terraform state file (a few KB). A monthly AWS Budget emails an alert at 20 percent of a $5 limit as a backstop.

## Repository layout

```
site/            Static concept site (HTML, images, video, film page)
api/             Feedback API: Lambda handler, validation, unit tests, local server, Dockerfile
infra/bootstrap/ One-time AWS setup: state bucket, GitHub OIDC role, budget alert
infra/preview/   The preview environment: S3, CloudFront, password gate, Lambda, DynamoDB
docker/          nginx config for the local stack
scripts/         Site asset check, feedback CSV export, backlog seeding
docs/            Client brief, architecture, decision records, runbook, backlog
.github/         CI, deploy, tear down and export workflows; PR template
```

## Quality gates

Every pull request runs: API unit tests (`node --test`), a site check that every referenced file and anchor exists, `terraform fmt` and `validate` on both stacks, and a Docker Compose smoke test that serves the site and round-trips a feedback submission.

## Notes

- Product photos and lifestyle scenes are AI-generated concept renders. The finished bag may look different.
- Code and content are not licensed for reuse. All rights reserved.
