# ADR 0002: Shared password checked by a CloudFront Function

**Status:** Accepted
**Date:** 2026-10-09

## Context

Only invited reviewers should see the concept. Reviewers are a handful of people the client knows, and they should not need to create an account.

Options considered:

1. **Per-person accounts** (Cognito, or an identity provider in front of CloudFront). Strongest control and per-person revocation, but every reviewer has to sign up, and it adds a user pool and login flow to maintain.
2. **Unlisted URL with no password.** Zero friction, but anyone who gets the link can open it.
3. **One shared username and password, enforced at the edge.** A CloudFront Function on viewer-request returns 401 with a Basic auth challenge unless the header matches.

## Decision

Option 3. It is the standard way agencies hand a client a staging link. It covers both the site and the API, runs before any origin is touched, and costs nothing extra.

## Consequences

- Rotating the password means updating the `PREVIEW_PASSWORD` secret and re-running **Deploy preview**. Everyone gets the new password at once; there is no per-person revocation.
- The password is embedded in the function code, so anyone with CloudFront read access in the AWS account can see it. Acceptable for a concept preview, not for customer data.
- Browsers remember Basic auth for the session; there is no logout button.
- If the client later needs per-person access or audit trails, move to option 1.
