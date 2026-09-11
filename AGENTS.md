# Instructions for AI agents

You are working in a repository created from the Secure Cloud Functions
Template. It deploys Cloud Functions, Cloud Run services, Workflows and Pub/Sub
to one GCP project with Terraform, where **adding a resource means adding a
folder, not writing Terraform**. Most tasks here should touch only YAML and
application code. Read this file fully before changing anything.

## The mental model

```
functions/<name>/terraform.yaml     -> a Cloud Function (+ optional cron)
cloudruns/<name>/terraform.yaml     -> a Cloud Run service (+ optional cron)
workflows/<name>/terraform.yaml     -> a Cloud Workflow (+ optional Eventarc trigger)
pubsubs/<name>/terraform.yaml       -> a Pub/Sub topic (+ pull sub, push to targets, GCS sink)
terraform.tfvars                    -> project settings and the list of secrets
examples/                           -> copy-from templates; NOTHING here is deployed
```

Each of the four directories is scanned for subdirectories containing a
`terraform.yaml`. **The directory name is the resource name**, and the `name:`
field inside must equal it. Every resource gets its own least-privilege service
account automatically.

Layers you should rarely or never edit:

| Path | Edit when |
|---|---|
| `functions/`, `cloudruns/`, `workflows/`, `pubsubs/` subdirectories | Normal work. This is where features live. |
| `terraform.tfvars` | Adding a secret name or a `template_variables` entry. |
| `*/main.tf` (the loaders), `modules/`, `infrastructure/`, `index.tf` | Only when the user explicitly asks to change the template itself. These encode the security model. |
| `.github/workflows/*.yaml` | Never edit the `workload_identity_provider` / `service_account` values by hand; `sbin/bootstrap` writes them. |
| `main.tf` backend block | Never. |

## The workflow for any change

1. Copy the closest example: `cp -r examples/function-cron functions/<name>`
2. Set `name:` in the new `terraform.yaml` to the directory name.
3. Edit the YAML and the code.
4. Run `sbin/check` — fmt, validate, tflint, tfsec, placeholder check. No cloud
   credentials needed. Fix everything it reports.
5. If credentials are available, `sbin/tf-plan` and read the plan.
6. Commit on a branch and open a PR. **Never push to `main`.**

CI runs `terraform plan` on the PR and comments it. Merging to `main` runs
`terraform apply` behind a human approval gate. **Do not run `terraform apply`
yourself** — the CI identity is the only thing that should apply, and Cloud Run
images only exist once CI has built them.

`sed -i '' ...` in the docs is macOS syntax; on Linux use `sed -i ...`.

## The YAML is validated at plan time — trust the errors

Unknown or misspelled keys, a `name:` that doesn't match the directory, a missing
required block, a `cron` with no `schedule`, a secret not declared in
`terraform.tfvars`, a Cloud Run folder with no `Dockerfile`, or a reference to a
function/service/topic/workflow that doesn't exist — all fail `terraform plan`
with a message naming the file, the key, and the valid options.

**When you see one of these errors, fix the YAML. Do not edit the loader to
accept the key.** The README in each directory is the schema:

- [functions/README.md](functions/README.md)
- [cloudruns/README.md](cloudruns/README.md)
- [workflows/README.md](workflows/README.md)
- [pubsubs/README.md](pubsubs/README.md)

Common key mistakes: it is `execution_timeout` not `timeout`; cron schedules
must be quoted (`"0 * * * *"`); Pub/Sub `ttl` is a duration string (`"604800s"`)
not a number; `owner` must be a valid GCP label value (lowercase, no spaces).

## Wiring resources together

Reference other resources by directory name. Every reference is checked at plan
time against what actually exists in this repo.

```yaml
# pubsubs/<name>/terraform.yaml — run a function/service for each message
pubsub:
  topic_name: orders
  push_to:
    - function: process-order          # must exist in functions/
    - cloudrun: order-api              # must exist in cloudruns/
      path: /pubsub

# workflows/<name>/terraform.yaml — let a workflow call things
functions: [process-order]             # grants invoker; missing => 403 at runtime
cloudruns: [order-api]
workflow-trigger:
  pubsub_topic: orders                 # must exist in pubsubs/
  criteria: [{attribute: type, value: google.cloud.pubsub.topic.v1.messagePublished}]
```

A function called from `workflow.yaml` but missing from `functions:` fails at
runtime with 403, not at plan — Terraform can't read the workflow body. Keep the
list in sync with the calls.

## Secrets

Secret **values never go in this repo** — not in YAML, not in tfvars, not in
code, not in commit messages. Terraform creates the container; a human adds the
value with `gcloud secrets versions add`.

1. Add the name to `secrets = [...]` in `terraform.tfvars`.
2. Reference it from a `terraform.yaml`:
   ```yaml
   secrets:
     - key: MY_ENV_VAR       # env var the code reads
       secret: my_secret     # the name from terraform.tfvars
       version: latest
   ```
3. Tell the user the value must be added before the resource that uses it can
   deploy (see [secrets/readme.md](secrets/readme.md) for the two-apply ordering).

Secrets have `prevent_destroy`. Removing a name from `secrets` makes the apply
fail on purpose. Do not work around this by editing `secrets/secrets.tf` unless
the user has explicitly asked to delete a secret and understands it is
irreversible.

Never `print()` or log a secret value in function code — Cloud Logging is
readable by far more people than can invoke the function.

## Service-specific rules

**Cloud Functions**: Python by default; `function_entrypoint` (default `main`)
must match a function in `main.py`. Everything in the folder ships except
`terraform.yaml`, `README.md`, `.DS_Store`. Don't leave a `.venv` or
`__pycache__` in there.

**Cloud Run**: needs a `Dockerfile` (or an explicit `image:`). The container
must listen on `$PORT` on `0.0.0.0`, not `localhost`. Never add `image: ...:latest`.
CI builds and pushes the image tagged with the commit SHA; you don't build anything.
`deletion_protection` is on by default — deleting or renaming a service folder
fails until it's set `false` and applied first.

**Workflows**: `workflow.yaml` is read verbatim. Cloud Workflows `${...}`
expressions are correct and must **not** be escaped as `$${...}`. Build URLs
from `sys.get_env("GOOGLE_CLOUD_PROJECT_ID")` / `GOOGLE_CLOUD_LOCATION`, never
hardcode a project or region.

**Pub/Sub push handlers** receive a POST with `{"message": {"data": "<base64>",
...}}`. Return 2xx to ack; anything else redelivers.

**Public endpoints**: `allow_unauthenticated: true` grants `allUsers` invoker.
Only set it if the user explicitly asks for a public endpoint, and say so in
your summary. The default (auth required) is deliberate.

## Things that look wrong but are deliberate — do not "fix" them

- `file()` not `templatefile()` for `workflow.yaml` — templatefile breaks on
  Cloud Workflows `${...}` syntax.
- The plan service account has **read-only** access to the state bucket and the
  plan workflow sets `TF_CLI_ARGS_plan=-lock=false`. Plan runs untrusted PR code;
  write access would let it poison state. Do not grant it write. Do not remove
  the env var.
- The apply workflow declares `environment: production`. The apply SA's
  workload-identity binding only matches that environment's token subject. Do
  not remove or rename it.
- `disable_on_destroy = false` on every API; `prevent_destroy` on the state
  bucket and secrets; `deletion_protection` on Cloud Run.
- `cloudrun_image_tag` has no default. CI sets it; `sbin/tf-plan` sets it
  locally. Don't add a default.
- `depends_on = [google_project_service.services]` throughout `infrastructure/`
  — orders creation after API enablement on fresh projects.
- `#tfsec:ignore:` comments each state their reason. A new tfsec finding is a
  real change; don't silence it without one.
- `moved {}` blocks in `infrastructure/moved.tf`, `modules/*/moved.tf` — state
  migrations for older repos. Harmless; leave them.
- `functions/`, `cloudruns/`, `workflows/`, `pubsubs/` contain only `.gitkeep`
  and a README in a fresh repo. That is correct — nothing is deployed until a
  folder is added.
- `roles/iam.serviceAccountUser` project-wide on the apply SA — see the comment
  in `infrastructure/permissions.tf` for why it can't be narrower.
- The loaders use `try(merge(x), {})` rather than a conditional — the
  conditional fails type-checking.

## Ask the user before

- Anything under `infrastructure/`, `modules/`, or a loader `main.tf`.
- Any IAM change, any `allow_unauthenticated: true`, any `ingress` change.
- Deleting a resource folder (it destroys the deployed resource on merge).
- Changing `region`, `bucket_location` or `project` in `terraform.tfvars` —
  these move or recreate resources.
- Removing a name from `secrets`.
- Editing `.github/workflows/`.

## Verifying your work

```bash
sbin/check              # always. no credentials needed.
sbin/tf-plan            # if you have credentials; read every line of the plan.
```

Read `terraform plan` output as a security reviewer would: every `+ create` of
an IAM member, every `allUsers`, every change to a service account is worth a
sentence in your summary. A docs-only change should produce an empty plan.

If `sbin/check` fails in `terraform init` with a registry/network error, the
static parts (fmt, placeholder check) still ran; say what was and wasn't checked
rather than reporting success.

## When something is missing from the template

If a task needs a key, resource type or wiring the YAML schema doesn't support,
that is a template change — stop and tell the user rather than working around it
with ad-hoc Terraform in a resource folder. Resource folders must contain only
`terraform.yaml`, code, and a README; a stray `.tf` file there is a red flag.

## If this is the template repository itself

You're in the template (not a repo created from it) if `terraform.tfvars` still
says `CHANGEME` or `github.event.repository.is_template` would be true. Changes
here affect every downstream repo. Keep examples inert, keep `sbin/check` green,
update the README table whenever you touch a loader's `allowed_*_keys`, and
update `MIGRATION.md` for anything that changes state addresses or required
inputs.
