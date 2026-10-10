# Client brief

**Client:** Shart Bag
**Prepared by:** Eric Shadwick
**Date:** October 2026
**Phase:** Concept review

## Background

Shart Bag is a pre-launch novelty product: a shark-shaped fanny pack that carries emergency bathroom supplies (spare underwear, wipes, seat covers, sanitizer, toilet spray). Each bag ships with a zipper charm from the "Shart Force," a cast of characters who also star in short films used for marketing. The physical product is going to a maker for samples. Before committing, the client wants a small group of people to see the concept and react to it.

## Goals

1. Present the product line, charms and kit in one place that looks like a real brand.
2. Collect structured feedback: favorite bag, favorite charm, purchase intent and free-text comments.
3. Keep the review site private to invited reviewers. (The source repository is public as a portfolio piece; the password-protected link is what reviewers use.)
4. Spend as close to nothing as possible when no review is running.

## In scope

- One-page concept site with the three bags, three charms, kit contents, field-test clips and the first short film.
- Feedback form and storage.
- A password-protected preview link that the client can turn on and off.
- Change request (2026-10-10): a server option with a link that never changes, switched on and off from GitHub, at a small fixed monthly cost (see ADR 0005).
- Export of feedback to a spreadsheet-friendly file.
- Local development environment, CI and infrastructure as code.

## Out of scope (this phase)

- Online ordering, payments and pricing (no maker quote yet).
- Custom domain and branded email.
- Analytics and tracking.
- Content management for non-technical editors.

## Acceptance criteria

| # | Criterion | How it is verified |
|---|---|---|
| 1 | Site loads on desktop and phone without horizontal scrolling | Manual check at 390 px and 1366 px wide |
| 2 | Every image, video and in-page link resolves | `scripts/check-site.mjs` in CI |
| 3 | Visitors without the password see only a login prompt | CloudFront Function returns 401; verified after deploy |
| 4 | A valid feedback submission is stored; an invalid one is rejected with field messages | API unit tests and the Compose smoke test in CI |
| 5 | The preview can be created and fully removed without using the AWS console | Deploy and Tear down workflows |
| 6 | No AWS access keys are stored in GitHub | Deploys use GitHub OIDC and a scoped IAM role |
| 7 | Feedback survives teardown | Tear down exports a CSV artifact before deleting the table |
| 8 | The server keeps the same link across stops and starts, and cannot be left running by mistake | Start and Stop workflows; nightly scheduled stop |
| 9 | The server cannot be reached except through the password gate | Deploy workflow security checks: 401 without a password, no answer at the server's own IP; nginx origin-secret test in CI |

## Open items

- Replace or crop the golf field-test clip: real golf brand logos are visible on the cart bag.
- Pricing, once the maker quotes.
- Trademark search on "Shart Bag" and "Steven Sharts" before any public launch.
