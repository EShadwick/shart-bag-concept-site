# ADR 0005: An EC2 server option with a fixed address, behind CloudFront

**Status:** Accepted
**Date:** 2026-10-10

## Context

The serverless preview (ADR 0001) costs almost nothing, but every deploy takes about 10 minutes and creates a new link, so the link has to be re-sent for each review. The client asked for a server that can be switched on when needed and keeps the same address, and accepted a small monthly cost for that.

Requirements:

- Same link every time.
- On and off from GitHub Actions, without the AWS console.
- Cannot be forgotten and left running.
- Same password gate and HTTPS as the preview, with no domain name to buy.

## Decision

Add a second, independent environment in `infra/server`:

- **One t4g.micro instance** (Amazon Linux 2023, arm64) runs the same Docker Compose app used for local development, with real DynamoDB instead of DynamoDB Local.
- **A fixed address.** An Elastic IP sits on a network interface created before the instance, so the server has its permanent address from the first second of first boot.
- **CloudFront in front.** It provides HTTPS on its default certificate (no domain needed), runs the same password function as the preview, and its link never changes while the stack exists.
- **Locked origin.** The security group accepts port 80 only from the AWS managed prefix list for CloudFront origin-facing servers. CloudFront also adds a secret header, and nginx returns 403 to any request without it. Another CloudFront distribution pointed at the address therefore cannot bypass the password.
- **No SSH.** No port 22 and no key pair. Deploys run through AWS Systems Manager Run Command.
- **Start, stop and nightly stop** are GitHub Actions workflows. The stop workflow also runs on a schedule at 09:17 UTC (off the hour, when GitHub is least likely to delay or drop it). A systemd timer on the server powers it off at 09:30 UTC as a backstop; the instance's shutdown behavior is "stop", so this never terminates it.
- **Code delivery:** the deploy workflow checks out the exact commit on the server (cloning first if needed), then runs `deploy/server/setup-host.sh` (Docker, Compose, Buildx, pinned and checksum-verified) and `deploy/server/deploy.sh`. That builds the API image with `docker build` (falling back to the classic builder if BuildKit has trouble on Amazon Linux's Docker 25), then runs `docker compose up --wait`.
- **The password stays at the edge.** CloudFront forwards the `Authorization` header to origins on POST, PUT, PATCH and DELETE even without an origin request policy. So the password function deletes the header after checking it, and the reviewer password never crosses the HTTP leg to the server.

## Cost (us-east-1, on-demand)

| Item | When billed | Price |
|---|---|---|
| t4g.micro | Running only | $0.0084/hour |
| Elastic IP | Always, running or stopped | $0.005/hour (about $3.65/month) |
| 8 GB gp3 disk | Always | $0.08/GB-month (about $0.64/month) |
| CloudFront, DynamoDB on-demand, SSM | Per request | Cents at review traffic |

Stopped all month: about $4.29. About 10 hours of demos a month: about $4.37. Left on 24/7: about $10.42. The instance uses `standard` CPU credits, so a busy CPU slows down rather than adding charges.

## Guardrails

- The deploy role can only launch `t4g.micro` or `t4g.small` (an explicit Deny on any other instance type). It is also denied Reserved Instance and Capacity Block purchases, Dedicated Hosts, capacity reservations, Spot and Fleet requests, and NAT gateways.
- Run Command is limited to the `AWS-RunShellScript` document on instances tagged `Name = shart-bag-server`.
- EC2 permissions are limited to one region. Most EC2 create calls cannot be scoped to resources that do not exist yet, so within that region the role has `ec2:*`, the same documented trade-off as CloudFront in ADR 0003.
- The instance role can only write to its own feedback table and read its own origin secret, plus the AWS managed Systems Manager policy.
- IMDSv2 is required. The hop limit is 2 so the API container can reach the instance role.

## Alternatives considered

- **Plain HTTP to the Elastic IP.** It's cheapest, but the shared password would cross the internet unencrypted. Rejected.
- **A domain name with Let's Encrypt on the instance.** It's a real option once the client owns a domain. CloudFront gives HTTPS today without one.
- **A start workflow that updates the CloudFront origin with the new public IP after each start.** It would avoid the Elastic IP charge, but it's slower and has more moving parts. The client chose the fixed address.
- **Lightsail.** It's cheaper per month for an always-on box, but it's a different toolset from the rest of the stack and offers less control over networking and IAM.

## Consequences

- There are two environments to keep in mind. They share the deploy role, the password secret and the state bucket (different state keys), and have separate feedback tables.
- While the server is stopped, the link shows a CloudFront error page. A friendly "offline" page is in the backlog.
- Operating system patching is manual for now (a redeploy runs `dnf` for Docker only). Patch Manager is in the backlog.
- Accepted risk: the CloudFront-to-server leg is plain HTTP, so the origin secret header crosses it unencrypted. Someone able to observe that traffic could replay the secret, but would still need a CloudFront distribution to get past the security group. A domain name with HTTPS to the origin would close this.
- Accepted risk: the deploy role can write inline policies on `shart-bag-server-*` roles, so whoever can run jobs in the GitHub `preview` environment could widen the server's permissions. In a shared AWS account, add a permissions boundary or give the project its own account.
- The server clones the repository anonymously, so the repository must stay public.
- Scheduled workflows are disabled by GitHub after 60 days without repository activity, so the nightly stop needs the repo to stay active, or the workflow re-enabled.
