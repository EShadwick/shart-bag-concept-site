# Runbook

Everything needed to set up, run, share and remove the Shart Bag preview. Values in `<ANGLE_BRACKETS>` are placeholders.

## 1. One-time setup

### Tools on your machine

- Git, Docker Desktop, Terraform 1.11 or newer, AWS CLI v2, GitHub CLI (`gh`).
- AWS credentials with admin rights for the first step only (`aws configure` or `aws sso login`). Check with `aws sts get-caller-identity`.

### Bootstrap AWS (once per AWS account)

```bash
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars   # set alert_email
gh api repos/<OWNER>/<REPO> --jq '"\ngithub_owner_id = \"\(.owner.id)\"\ngithub_repo_id  = \"\(.id)\""' >> terraform.tfvars
terraform init
terraform apply
terraform output
```

The `gh api` line adds the repo's numeric owner and repo IDs. GitHub puts them in the OIDC subject for repositories created after 2026-07-15 (see ADR 0003); skip that line for an older repository.

This creates the Terraform state bucket, the GitHub OIDC provider, the deploy role and a $5 monthly budget alert. If `apply` fails because the GitHub OIDC provider already exists, set `create_github_oidc_provider = false` in `terraform.tfvars` and apply again.

Confirm the budget alert subscription from the AWS email when it arrives.

The bootstrap state is a local file (`infra/bootstrap/terraform.tfstate`, git-ignored). Keep a copy somewhere safe; you need it to change or remove the bootstrap later.

### Connect GitHub (once per repo)

Use the bootstrap outputs:

```bash
gh api -X PUT repos/<OWNER>/<REPO>/environments/preview
gh variable set AWS_REGION        --body "<AWS_REGION>"
gh variable set TF_STATE_BUCKET   --body "<STATE_BUCKET>"
gh variable set AWS_DEPLOY_ROLE_ARN --env preview --body "<DEPLOY_ROLE_ARN>"
gh secret set PREVIEW_PASSWORD    --env preview          # prompts; 12+ characters
```

Or in the browser: **Settings → Environments → New environment → `preview`**, then add the variables and secret there and under **Settings → Secrets and variables → Actions**.

Optional: on the `preview` environment, add yourself as a required reviewer so every deploy and teardown waits for your approval. The nightly **Server: stop** would then wait for approval too; the timer on the server still stops it at 09:30 UTC.

## 2. Run locally

```bash
docker compose up --build    # http://localhost:8080
docker compose down
```

Unit tests without Docker: `cd api && npm ci && npm test`.

## 3. Start a review

1. **Actions → Deploy preview → Run workflow.**
2. Open the run summary for the link. A new CloudFront distribution can take a few minutes before it answers.
3. Deploy checklist (things CI cannot test):
   - Opening the link asks for a username and password; Cancel shows "Unauthorized".
   - Username `client` plus the password shows the site; both video clips play.
   - The film page opens and the back link returns to the site.
   - Submitting the feedback form shows "Thanks. Your feedback was saved."
4. Send reviewers the link, the username `client` and the password, ideally in separate messages.

## 4. Read feedback

**Actions → Export feedback → Run workflow** (source `preview`), then download the `preview-feedback-<run id>` artifact (CSV, newest first).

## 5. End a review

**Actions → Tear down preview → Run workflow**, type `teardown`.

The workflow exports feedback to a CSV artifact (kept 90 days), then deletes the site bucket and files, CloudFront distribution, password function, Lambda, logs and the feedback table. The link stops working. Deleting a CloudFront distribution takes several minutes; the run waits for it.

## 6. Server environment (EC2, fixed link)

Design and costs: [ADR 0005](adr/0005-ec2-server-option.md). It uses the same GitHub `preview` environment, deploy role and password secret as the preview. The repository must stay public: the server pulls the code with an anonymous `git clone`.

**One time, if the bootstrap was applied before the server option existed:** re-apply it so the deploy role gets the EC2 and Systems Manager permissions.

```bash
aws login
cd infra/bootstrap
terraform apply   # expect: 0 to add, 2 to change (the deploy role and its policy), 0 to destroy
```

| Task | How | Notes |
|---|---|---|
| Create it, or ship the latest commit | Actions → **Server: create or update** | First run about 15 minutes. Later runs apply infrastructure changes, start the server if needed and put the commit live through SSM. |
| Start | Actions → **Server: start** | About 2 minutes. Same link every time. |
| Stop | Actions → **Server: stop** | Also runs every night at 09:17 UTC. A timer on the server powers it off at 09:30 UTC in case that run is late or skipped. |
| Export feedback | Actions → **Export feedback** → `server` | Download the `server-feedback-<run id>` artifact. |
| Delete | Actions → **Server: delete** → type `delete` | Exports feedback, then removes the server, its IP, network, table and link. Ends all server charges. |

From Git Bash, the same with the GitHub CLI:

```bash
gh workflow run server-deploy.yml
gh workflow run server-start.yml
gh workflow run server-stop.yml
gh workflow run export-feedback.yml -f source=server
gh workflow run server-delete.yml -f confirm=delete
gh run watch
```

Deploy checklist (after the first create):

- The run's "Security checks" step passed: 401 without a password, and the server's IP does not answer directly.
- The link asks for the username and password, then shows the site; both clips play; the film page opens.
- A feedback submission shows "Thanks. Your feedback was saved." and appears in **Export feedback** → `server`.
- After **Server: stop**, the link shows an error page; after **Server: start**, it works again with no other changes.

Looking at the server without SSH: AWS console → Systems Manager → Session Manager → Start session → `shart-bag-server`. Useful commands: `sudo docker compose -f /opt/shart-bag/app/deploy/server/compose.yml ps` and `sudo cat /var/log/cloud-init-output.log` (first boot).

## 7. Change the password

Update the `PREVIEW_PASSWORD` secret on the `preview` environment, then run **Deploy preview** (and/or **Server: create or update**) again. The old password stops working once CloudFront picks up the new function, usually within a few minutes.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Deploy fails at "Configure AWS credentials" with "Not authorized to perform sts:AssumeRoleWithWebIdentity" | The token's `sub` does not match the trust policy: missing or wrong `github_owner_id`/`github_repo_id`, job not in the `preview` environment, or owner/repo spelled differently (case matters) | Compare `terraform output github_oidc_subject` (in `infra/bootstrap`) with the `sub` from `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity --max-results 1`, fix `terraform.tfvars`, re-apply bootstrap |
| Terraform `AccessDenied` on a resource | Resource name does not start with `shart-bag-preview-`, or a permission is missing from the deploy role | Keep the naming; add the missing action to `infra/bootstrap/main.tf` and re-apply bootstrap |
| "Error acquiring the state lock" | A previous run was cancelled mid-apply | Confirm no other run is active, then `terraform force-unlock <LOCK_ID>` locally with the same backend config |
| Link errors or times out right after deploy | CloudFront still propagating | Wait a few minutes and retry |
| Password prompt keeps coming back | Wrong username or password | Username is `client`; check the secret value |
| Feedback form says "Could not save feedback" | Lambda error | Check the function's CloudWatch log group `/aws/lambda/shart-bag-preview-feedback` |
| Server link shows a 502 or 504 error | Server is stopped, or still booting | Run **Server: start**, or wait a minute |
| "Server: create or update" fails at "Put this commit live" | First-boot setup or deploy script failed on the server | The step prints the script output. More detail: Session Manager → `sudo cat /var/log/cloud-init-output.log` |
| Server workflows fail with `AccessDenied` on EC2 or SSM | Bootstrap not re-applied since the server option was added | Re-apply `infra/bootstrap` (section 6) |
| Nightly stop stopped running | GitHub disables scheduled workflows after 60 days without repository activity | Actions → **Server: stop** → Enable workflow |

## Removing everything

1. Run **Tear down preview** and **Server: delete**.
2. Empty the state bucket, including old versions (S3 console → bucket → Empty).
3. `cd infra/bootstrap && terraform destroy`.
