# Secure Cloud Functions Template

Spin up Cloud Functions, Cloud Run services, cron jobs, Workflows and Pub/Sub in
GCP with Terraform, where every resource gets a dedicated least-privilege service
account and secure defaults, and adding a new one means creating a folder — not
writing Terraform.

- [Quickstart](#quickstart) — get from clone to deployed
- [Adding things](#adding-things) — functions, Cloud Run, workflows, pub/sub, secrets
- [How CI works](#cicd) — plan on PRs, apply on merge
- [Security design](#security-design) — why there are two service accounts
- [Troubleshooting](#troubleshooting) — the errors you will actually hit

---

## Quickstart

You need `gcloud`, `terraform` (1.5 or newer, below 2.0) and `python3`
installed, a GCP project you have `roles/owner` on, and a GitHub repo created
from this template.

### 1. Run the bootstrap script

```bash
gcloud auth login && gcloud auth application-default login
sbin/bootstrap
```

It asks for your project, region, bucket location, GitHub repo and owning team,
then handles the setup that used to be a manual checklist: creating the state bucket, writing
`terraform.tfvars`, pointing the backend at your bucket, running
`terraform init`, importing the buckets, and rewriting the two GitHub Actions
workflows with your real workload-identity provider and service account emails.

It is safe to re-run — every step checks the current state before changing
anything. It enables the ~37 required APIs first and waits for them, so the
first `apply` no longer races them.

### 2. Create the `production` GitHub Environment

**Do this before you merge anything.** Under
**Settings > Environments > New environment**, create `production` and add:

- **Required reviewers** — so a human approves before the privileged service
  account is used.
- **Deployment branches** — "Selected branches", limited to `main`.

This is load-bearing, not cosmetic. See
[Why `production` is required](#why-production-is-required).

### 3. Commit and push

```bash
git add -A && git commit -m "bootstrap: configure for my-project"
git push
```

Opening a PR runs `terraform plan` and comments the result if there are changes.
Merging to `main` runs `terraform apply` after your reviewer approves.

### 4. Add your first function

```bash
cp -r examples/function-cron functions/hello
sed -i '' 's/^name: .*/name: hello/' functions/hello/terraform.yaml
```

The directory name and the `name:` field must match — that's all the renaming
takes. This example wants the `test_key_1` secret; either add it (see
[secrets/readme.md](secrets/readme.md)) or delete the `secrets:` block from
`functions/hello/terraform.yaml`.

Open a PR and read the plan. That's the whole loop.

> Prefer to do it by hand? Run `sbin/bootstrap` anyway and read what it prints —
> it's the same steps, in order, with the values filled in.

---

## Adding things

Each of `functions/`, `cloudruns/`, `workflows/` and `pubsubs/` is scanned for
subdirectories containing a `terraform.yaml`. **The directory name is the
resource name**, and the `name:` field inside must match it.

| I want a… | Read | Start from |
|---|---|---|
| Cloud Function, optionally on a schedule | [functions/README.md](functions/README.md) | `examples/function-cron` |
| Cloud Run service from a Dockerfile | [cloudruns/README.md](cloudruns/README.md) | `examples/cloudrun-basic` |
| Cloud Workflow, optionally event-triggered | [workflows/README.md](workflows/README.md) | `examples/workflow-basic` |
| Pub/Sub topic that pushes to a function or service | [pubsubs/README.md](pubsubs/README.md) | `examples/pubsub-to-function` |
| Pub/Sub topic with a pull subscription or GCS archive | [pubsubs/README.md](pubsubs/README.md) | `examples/pubsub-basic` |
| secret | [secrets/readme.md](secrets/readme.md) | — |
| shared Python library | [libraries/README.md](libraries/README.md) | `libraries/example` — not built or published by CI yet |

Nothing in [examples/](examples/) is deployed; copy from it. Unknown or
misspelled keys in a `terraform.yaml` are a **plan-time error** naming the file
and the key, so a typo can't silently deploy the wrong thing. A `name:` that
doesn't match its directory, a missing required block, a `cron` without a
`schedule`, or a Cloud Run folder with neither a `Dockerfile` nor an `image:`
fail the same way. So does any cross-reference — a workflow calling a function,
a topic pushing to a service, a trigger naming a topic — whose target isn't
defined in this repo.

### Wiring things together

The directories reference each other by name, and every reference is checked at
plan time:

| From | Key | To |
|---|---|---|
| `pubsubs/` | `pubsub.push_to: [{function: x}, {cloudrun: y}]` | delivers each message to `functions/x` or `cloudruns/y` |
| `workflows/` | `functions: [x]`, `cloudruns: [y]` | grants the workflow invoker on them |
| `workflows/` | `workflow-trigger.pubsub_topic: t` | runs the workflow when a message lands on a topic from `pubsubs/` |

### Referencing config values from YAML

A value of `$name` in `environment_variables` is substituted from
`terraform.tfvars`:

```yaml
environment_variables:
  GCP_PROJECT: $project      # -> your project id
  GCP_REGION: $region
  LITERAL: hello             # no $, passed through unchanged
```

`project`, `region`, `zone` and `owner` always work. Add your own under
`template_variables` in `terraform.tfvars`:

```hcl
template_variables = {
  slack_channel = "#alerts"
}
```

A `$name` with no match is passed through unchanged, `$` included.

### Checking your work locally

```bash
sbin/check         # the static checks CI runs (tflint/tfsec skipped if not installed); no cloud credentials
sbin/check --fix   # reformat in place
sbin/tf-plan       # plan, with output split into create/delete lists (needs jq and bash 4.1+)
```

To run Terraform locally as a service account without a key file,
`eval "$(sbin/gcloud-auth-export-access-token <sa-email>)"` exports a one-hour
token minted through your own `gcloud` login. Set `REQUIRE_LOGIN_DOMAIN` to
refuse non-org accounts.

---

## CI/CD

`terraform plan` runs on pull requests and comments the output when there are
changes ([workflow](.github/workflows/terraform-plan.yaml)). `terraform apply`
runs on merge to `main` ([workflow](.github/workflows/terraform-apply.yaml)).
Both are gated behind [static checks](.github/workflows/terraform-checks.yaml) —
a Terraform version check, a check that no `CHANGEME` placeholders remain,
`fmt`, `validate` (with `-backend=false`), tflint (config in
[.tflint.hcl](.tflint.hcl)) and tfsec — which need no credentials and fail in
seconds. `sbin/check` runs the same set locally. The few tfsec findings the
design accepts on purpose (the apply SA's `*.admin` roles, project-wide
`serviceAccountUser`, Google-managed bucket encryption) are suppressed inline
with a `#tfsec:ignore` comment stating why, so a new finding is always a real
change.

In the template repository itself the placeholder check is skipped (gated on
`github.event.repository.is_template`), because the `CHANGEME` values are meant
to be there. Repos created from the template enforce it.

Cloud Run images follow the same split. On a PR every `cloudruns/*/Dockerfile`
is built — but not pushed, and with no cloud credentials — so a broken
Dockerfile fails at review time. On merge the apply job builds each image, pushes
it to Artifact Registry tagged with the commit SHA, then runs `terraform apply`
with `TF_VAR_cloudrun_image_tag` set to that SHA.

Plan runs as the **read-only** `gha-cf-tf-plan` identity. Apply runs as the
privileged `gha-cloud-functions-deployment` identity inside the protected
`production` environment, so it waits for reviewer approval first. A new push to
a PR cancels the in-flight plan for that PR; applies never cancel each other and
queue instead, so two can't race for the state lock.

---

## Security design

### Two deployment identities

This template provisions **two** service accounts, because `terraform plan` runs
on pull requests and therefore executes attacker-controllable configuration —
a `data "external"` block or a custom provider runs arbitrary code during
`plan`, with whatever credentials the job holds.

- **`gha-cf-tf-plan`** — read-only, used by the plan workflow. It gets
  `roles/viewer`, `roles/iam.securityReviewer` (IAM-policy reads),
  `roles/iam.workloadIdentityPoolViewer`, a custom role for
  `storage.buckets.get`, **read-only** access to the state bucket, and object
  read on the staging bucket only. It cannot write resources, cannot read secret
  values, and cannot read object contents of other buckets (e.g. Pub/Sub sinks).
- **`gha-cloud-functions-deployment`** — privileged, used by the apply workflow.
  Holds **no** `secretmanager.secretAccessor`: secret *management* (create, set
  IAM) is granted through a narrow custom role that cannot read values. It does
  hold project-wide `roles/iam.serviceAccountUser` so it can `actAs` the
  per-resource runtime SAs it deploys — see the NOTE in
  [infrastructure/permissions.tf](infrastructure/permissions.tf) for why that
  can't be scoped tighter and what the locked-down alternative costs.

The plan identity has **read-only** access to Terraform state, deliberately. If
it could write there, untrusted PR code could overwrite the state file and the
next apply on `main` would act on poisoned state — deleting resources or
re-pointing them elsewhere. Read-only means plan can't take the state lock
either, so the plan workflow sets `TF_CLI_ARGS_plan=-lock=false`. That's safe
(plan never writes state) and it fails closed: drop the env var and the job
errors out rather than silently regaining write access.

### Why `production` is required

The apply SA's workload-identity binding is pinned to the GitHub **`production`
environment subject** (`repo:<org>/<repo>:environment:production`), not merely to
`refs/heads/main`. The approval gate is therefore enforced at the **GCP IAM
layer**: only a job declaring `environment: production` can mint that token, and
no other `main`-triggered workflow can.

**If you don't create the environment, GitHub auto-creates it on first use with
no protection and a default policy of "all branches"** — at which point any pull
request branch can declare `environment: production` and mint the privileged
token, defeating the plan/apply split entirely. Creating it with a `main`-only
deployment branch rule is what closes that hole.

### Bootstrap note

Neither CI identity holds project-IAM-admin, so any apply that changes
**project-level IAM** — including granting the plan SA its roles on first run —
must be run by a principal with `roles/owner` or
`roles/resourcemanager.projectIamAdmin`. `sbin/bootstrap` runs that first apply
as you.

### Secure defaults

- Every function, Cloud Run service, workflow, cron, Eventarc trigger and
  Pub/Sub subscription gets its **own** runtime service account, granted only
  what its `terraform.yaml` declares (plus `roles/logging.logWriter`).
- Cloud Run images are built in CI and deployed by immutable per-commit tag, so
  a running revision always maps to a reviewed commit. Services have
  `deletion_protection` on by default, so deleting a folder fails the apply
  instead of tearing down a live service.
- Functions and Cloud Run services **require authentication** unless you
  explicitly set `allow_unauthenticated: true`.
- All buckets are created with public access prevention and uniform
  bucket-level access; the state bucket is versioned and has
  `prevent_destroy`.
- Secrets are `prevent_destroy`, so removing a name from `secrets` can't
  silently delete every version of it.
- `max_instances` defaults to 10, bounding the cost of a runaway loop.
- APIs are `disable_on_destroy = false`, so a stray `terraform destroy` can't
  disable 37 APIs project-wide.

> **Note on `ingress_settings`:** the default is `ALLOW_ALL`, meaning the
> function's endpoint is reachable from the internet — but **callers still need
> `roles/cloudfunctions.invoker`**, so reachable is not the same as callable.
> `ALLOW_ALL` is the default because Cloud Scheduler and other Google services
> reach functions over the public endpoint, and internal-only ingress can break
> the cron path depending on your project's networking. If a function doesn't
> need to be publicly reachable, set `ingress_settings:
> ALLOW_INTERNAL_AND_GCLB` on it and verify its callers still work. Cloud Run
> has the same shape under the `ingress` key, defaulting to `INGRESS_TRAFFIC_ALL`
> with `roles/run.invoker` still required.

---

## BYO workload identity provider and service account

Sentry employees can create a service account in
[security-as-code](https://github.com/getsentry/security-as-code) and grant it
access to the existing workload identity pool instead of creating a new one.
Create it in
[iac-security/env/prod/terraform.tfvars](https://github.com/getsentry/security-as-code/blob/main/iac-security/env/prod/terraform.tfvars)
and grant it access to your repo
([example](https://github.com/getsentry/security-as-code/blob/beed2427d34b22edb44dfad2a822389b4a6c352c/iac-security/env/prod/terraform.tfvars#L184-L190)).

Then:

- set `deploy_sa_email` in `terraform.tfvars` to that account
- update the `workload_identity_provider` and `service_account` in both
  `.github/workflows/terraform-plan.yaml` and
  `.github/workflows/terraform-apply.yaml`

> **BYO mode and the plan/apply split:** when `deploy_sa_email` is set this repo
> does **not** create the two accounts — you bring one. To keep the same
> least-privilege benefit, create a separate read-only account for the plan
> workflow and a privileged one (pinned to the `production` environment subject)
> for apply, then point each workflow at the matching account. `sbin/bootstrap`
> will fill in the provider and apply account but warns that the plan account
> is yours to set.

For local runs against a security-as-code terraformer account,
`eval "$(sbin/sac-terraform-auth ...)"` resolves the account with
`sac-terraformer` and mints a token via `sbin/gcloud-auth-export-access-token`;
`sbin/sac-terraform-auth-as-me` does the same with your own login.

---

## Troubleshooting

**`Error: ... API has not been used in project ... before or it is disabled`**
Rare now: `sbin/bootstrap` pre-enables every API and Terraform orders resources
after them. If it still happens, wait a few minutes and re-run `terraform apply`.

**`No value for required variable "cloudrun_image_tag"`**
Cloud Run images are built only by CI, so there's no default tag to deploy. Use
`sbin/tf-plan` (it passes the current commit), or add
`-var cloudrun_image_tag=<sha>`.

**Pub/Sub push returns 401 and nothing runs**
On projects created before 2021-04-08 the Pub/Sub service agent needs a one-off
grant to impersonate the push identity — see
[examples/pubsub-to-function](examples/pubsub-to-function/README.md#older-projects).

**`Found unreplaced CHANGEME placeholders`**
Run `sbin/bootstrap`, or fill in `terraform.tfvars`, the backend `bucket` in
`main.tf`, and the auth inputs in `.github/workflows/`. The check skips
`examples/`, so placeholders there are fine. `sbin/check` reports this in a
clone of the template repo itself too — expected there, and CI skips it.

**`functions/x/terraform.yaml has unknown key(s) ...`** (or `cloudruns/`,
`workflows/`, `pubsubs/`)
A typo, or a key that belongs in a different block. The message lists the valid
keys; see the README in that directory.

**`cloudruns/x/ has no Dockerfile`**
Every Cloud Run folder needs a `Dockerfile` for CI to build, or an explicit
`image:` under `cloud-run` pointing at an image built elsewhere.

**`... references secret(s) not declared in the root `secrets` list`**
Add the name to `secrets` in `terraform.tfvars`, then add its value —
see [secrets/readme.md](secrets/readme.md).

**`Error 409: The requested bucket name is not available`**
GCS bucket names are globally unique. Sink buckets are prefixed with your
project name to avoid this; if you hit it anyway, pick a different `sink_name`.

**Cloud Run deploy fails a health check / times out starting**
The container isn't listening on `$PORT`, or is bound to `localhost` instead of
`0.0.0.0`. See [cloudruns/README.md](cloudruns/README.md).

**`Error creating Job: googleapi: Error 404: ... function not found`**
The function and the resource invoking it are in different regions. Everything
now takes its region from the single `region` variable, so this should only
happen if you've overridden a region somewhere by hand.

**`Error acquiring the state lock`** on the plan job
Expected if `TF_CLI_ARGS_plan=-lock=false` was removed from
`.github/workflows/terraform-plan.yaml`. The plan identity has read-only state
access on purpose — put the env var back rather than granting it write.

**Upgrading an existing repo built from an older version of this template?**
See [MIGRATION.md](MIGRATION.md).
