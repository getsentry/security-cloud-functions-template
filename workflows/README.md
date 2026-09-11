# Cloud Workflows

Every subdirectory of `workflows/` that contains a `terraform.yaml` becomes a
Cloud Workflow. **The directory name is the workflow name** — the `name:` field
inside must match it. Each folder needs two files:

- `workflow.yaml` — the workflow definition itself (GCP syntax)
- `terraform.yaml` — what Terraform should create and grant

## Add one

```bash
cp -r examples/workflow-basic workflows/my-workflow
sed -i '' 's/^name: .*/name: my-workflow/' workflows/my-workflow/terraform.yaml
```

Then edit `workflow.yaml`, and list every function it calls under `functions:`.

## `${...}` expressions work

`workflow.yaml` is read verbatim, so Cloud Workflows expressions reach GCP
untouched:

```yaml
main:
  steps:
    - init:
        assign:
          - project: ${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
          - location: ${sys.get_env("GOOGLE_CLOUD_LOCATION")}
          - url: ${"https://" + location + "-" + project + ".cloudfunctions.net/my-function"}
    - call_it:
        call: http.post
        args:
          url: ${url}
          auth:
            type: OIDC
            audience: ${url}
```

> Earlier versions of this template ran `workflow.yaml` through Terraform's
> `templatefile()`, which tried to evaluate those `${...}` as HCL and failed with
> *"Extra characters after interpolation expression"*. Any workflow using an
> expression was unbuildable, which is why the old examples hardcoded full
> function URLs. Use `sys.get_env` as above instead of hardcoding a project.

Useful runtime env vars: `GOOGLE_CLOUD_PROJECT_ID`,
`GOOGLE_CLOUD_PROJECT_NUMBER`, `GOOGLE_CLOUD_LOCATION`,
`GOOGLE_CLOUD_WORKFLOW_ID`.

## Reference

| Key | Description | Required | Default |
|---|---|---|---|
| `name` | Must equal the directory name | yes | — |
| `description` | Free text | no | null |
| `functions` | Functions in `functions/` this workflow calls | no | `[]` |
| `cloudruns` | Cloud Run services in `cloudruns/` this workflow calls | no | `[]` |
| `bucket` | GCS buckets this workflow reads | no | `[]` |
| `workflow` | Other workflows in `workflows/` this workflow calls | no | `[]` |
| `workflow-trigger` | Create an Eventarc trigger | no | — |

### `workflow-trigger`

| Key | Description | Required |
|---|---|---|
| `criteria` | List of `{attribute, value}` event filters. Must include `type`. | yes |
| `pubsub_topic` | A topic from `pubsubs/` to consume. Omit and Eventarc creates its own. | no |

```yaml
workflow-trigger:
  pubsub_topic: orders
  criteria:
    - attribute: type
      value: google.cloud.pubsub.topic.v1.messagePublished
```

Creates an Eventarc trigger named `<name>-trigger` with its own service account
`earc-<name>-trigger`. Name a `pubsub_topic` and the trigger consumes that topic,
so publishing to it runs the workflow. Leave it out and Eventarc creates an
anonymous topic — `terraform output eventarc_topics` tells you its name.

## Names are checked at plan time

Every name under `functions`, `cloudruns`, `workflow` and `pubsub_topic` must
exist in the matching directory of this repo. A typo fails `terraform plan` with
the list of names that do exist, instead of failing at apply with a 404 — or, for
an invoker grant on a function that exists but isn't listed, at runtime with 403.

## Permissions

Everything the workflow can do comes from its `terraform.yaml`:

- `functions:` → `cloudfunctions.invoker` **and** `run.invoker` on each named
  function (gen2 functions are Cloud Run underneath, so an OIDC call needs both)
- `cloudruns:` → `run.invoker` on each named service
- `bucket:` → `storage.objectViewer` on each named bucket
- `workflow:` → project-wide `roles/workflows.invoker`

**A function called from `workflow.yaml` but missing from `functions:` fails at
runtime with 403**, not at plan time — Terraform can't read your workflow
definition to check. If a workflow returns 403, this is the first thing to look
at.

> `workflow:` grants **project-wide** `roles/workflows.invoker`, because the
> provider exposes no per-workflow IAM resource and the Workflows API doesn't
> support `resource.name` IAM conditions. Leave it out unless you need it; see
> the note in [modules/cloud-workflow/main.tf](../modules/cloud-workflow/main.tf).
