## What changed

<!-- One or two sentences. Link the issue: Closes #<ISSUE_NUMBER> -->

## Client-facing?

- [ ] Yes, reviewers will see this change
- [ ] No, internal only (infra, CI, docs)

## How it was tested

- [ ] `docker compose up --build` and checked http://localhost:8080
- [ ] `cd api && npm test`
- [ ] `node scripts/check-site.mjs`
- [ ] `terraform fmt -check -recursive infra` and `terraform validate`
- [ ] Deployed to the preview and ran the deploy checklist in docs/runbook.md (infra changes only)

## Screenshots

<!-- For site changes: desktop and phone width. -->
