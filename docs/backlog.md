# Backlog

Seed these as GitHub issues with `scripts/seed-issues.sh`. Each delivered item is meant to land through its own branch and pull request.

## Delivered in the concept phase

| # | Item | Labels |
|---|---|---|
| 1 | Client brief and acceptance criteria | docs |
| 2 | Concept site: bags, charms, kit, field-test clips, film | site |
| 3 | Feedback form and API with validation and tests | api |
| 4 | Local environment with Docker Compose | devops |
| 5 | CI: unit tests, site check, Terraform validate, Compose smoke test | devops |
| 6 | AWS bootstrap: state bucket, GitHub OIDC role, budget alert | infra |
| 7 | Preview environment: S3, CloudFront, password gate, Lambda, DynamoDB | infra |
| 8 | Deploy, tear down and export workflows | devops |
| 9 | Server option: EC2 with a fixed address behind CloudFront, start/stop/nightly stop | infra, devops |

## Open

| # | Item | Labels |
|---|---|---|
| 10 | Replace or crop the golf clip: real golf brand logos are visible | site, client-request |
| 11 | Accessibility pass: keyboard-only and screen reader walkthrough | site |
| 12 | Add pricing once the maker quotes | site, blocked |
| 13 | Custom domain and certificate for the preview | infra, future |
| 14 | Missions 2 to 4 of Shart Force Films | site, future |
| 15 | Friendly "server is offline" page instead of the CloudFront error while the server is stopped | infra |
| 16 | Operating system patching for the server (Systems Manager Patch Manager) | infra, devops |
