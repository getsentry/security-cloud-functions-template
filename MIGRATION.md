# Migrating an existing repo

Only relevant if your repo was created from an older version of this template
and already has Terraform state. New repos should just run `sbin/bootstrap`.

Read the plan before applying. Terraform's `moved` blocks handle the state
renames automatically, so most of this is editing `terraform.tfvars`.

## 1. Update `terraform.tfvars`

`project_id` and `tf_state_bucket` are gone. `project_id` was always the same
value as `project`, and `tf_state_bucket` was declared but never read — two
extra chances to get setup wrong.

```diff
-project_id      = "my-project"
-tf_state_bucket = "my-project-tfstate"
```

Two new variables:

```hcl
# Secrets are no longer hardcoded in secrets/secrets.tf. List the ones you
# actually use -- copy them from the old `local.secrets` in that file.
secrets = ["test_key_1", "GH_APP_ID", "GH_APP_INSTALLATION_ID", "GH_APP_PRI_KEY"]

# Optional. Values you want to reference from a terraform.yaml as $name.
template_variables = {}
```

> **Get the `secrets` list right before you apply.** Secrets now have
> `prevent_destroy`, so a missing name makes the apply fail rather than delete
> the secret — the safe direction, but you'll have to fix it and re-run.

## 1b. `bucket_location` now applies to the state and staging buckets

The old template hardcoded both to `location = "US"` and only used
`bucket_location` for Pub/Sub sink buckets. Now every bucket uses it. A bucket's
location cannot be changed in place, so if your `bucket_location` is anything
other than `US`, the plan will try to **replace both buckets** — the staging
bucket silently, and the state bucket with:

```
Error: Instance cannot be destroyed
Resource module.infrastructure.google_storage_bucket.tf-state has
lifecycle.prevent_destroy set, but the plan calls for this resource to be destroyed.
```

That error is the guard working. Fix it by matching the config to what exists:

```hcl
bucket_location = "US"
```

Only choose a regional value in a brand-new project, where `sbin/bootstrap`
creates the state bucket in that location from the start.

## 2. `$name` substitution changed

Values available to `terraform.yaml` used to come from regex-parsing
`terraform.tfvars`, which broke on any multi-line value. They now come from an
explicit map.

`project`, `region`, `zone` and `owner` still work. **`$project_id` no longer
resolves** — change it to `$project`:

```diff
 environment_variables:
-  GCP_PROJECT: $project_id
+  GCP_PROJECT: $project
```

Anything else you were relying on must be listed under `template_variables`.

## 3. `workflow.yaml` is no longer templated

Workflow definitions are read with `file()` instead of `templatefile()`, so
Cloud Workflows `${...}` expressions now work as written. If you had escaped
them as `$${...}` to work around the old behaviour, unescape them:

```diff
-          - x: $${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
+          - x: ${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
```

## 4. Region

Cloud Functions previously ignored `region` and always deployed to `us-west1`
(the module default), while their cron triggers used `region`. **If your `region`
is not `us-west1`, this apply will move every function** — read the plan
carefully and expect recreation.

If your region *is* `us-west1`, nothing moves.

## 5. Examples moved

`functions/example-gen2-cron`, `functions/get-gh-app-token`,
`workflows/example1`, `workflows/example-eventarc`, `pubsubs/example-pubsub` and
`pubsubs/example-pubsub-sink` now live under `examples/` and are **not
deployed**.

If you were running any of them for real, copy it back:

```bash
cp -r examples/function-cron functions/example-gen2-cron
sed -i '' 's/^name: .*/name: example-gen2-cron/' functions/example-gen2-cron/terraform.yaml
```

Otherwise the plan will show them being destroyed, which is what you want.

## 6. Pub/Sub sinks now export

A `sink` block used to create an empty bucket that nothing wrote to. It now also
creates an export subscription (`<sink_name>-gcs-export`) and grants the Pub/Sub
service agent write access, so messages actually land in the bucket.

**The bucket name also gains a project prefix** (`<project>-<sink_name>`), so
the old bucket will be destroyed and a new one created. Copy anything you need
out of the old bucket first:

```bash
gcloud storage cp -r gs://old-sink-name gs://my-project-old-sink-name
```

## 7. State-bucket IAM

The plan service account's access to the state bucket drops from
`roles/storage.objectUser` (read **and write**) to `roles/storage.objectViewer`
(read only) — see the security note in `infrastructure/main.tf` for why.

Two knock-on effects:

- The plan workflow now sets `TF_CLI_ARGS_plan=-lock=false`, because a read-only
  identity can't write a lock object. That's already in the updated workflow
  file; keep it.
- **Run this apply as a human admin** (`roles/owner` or
  `roles/resourcemanager.projectIamAdmin`), not via CI. It rewrites IAM on the
  state bucket, including the apply SA's own access, and the CI identities
  deliberately cannot grant IAM.

## 8. Cloud Run is new

`cloudruns/` and its Artifact Registry repository are additive -- if you have no
Cloud Run services the only change is one new empty repository and the
`roles/artifactregistry.admin` grant on the apply SA.

The new `cloudrun_image_tag` variable defaults to `latest` and CI overrides it,
so there is nothing to set in `terraform.tfvars`.

## 8b. Round-two changes

- **`cloudrun_image_tag` is now required** (it defaulted to `latest`, which CI
  never pushes). `sbin/tf-plan` and `sbin/bootstrap` set it for you; other local
  Terraform invocations need `-var cloudrun_image_tag=<sha>`. CI is unchanged.
- **Pub/Sub pull subscriptions are optional.** The addresses gain a `[0]` index;
  `modules/pubsub/moved.tf` migrates existing state, so the plan shows moves, not
  replacements. `service_account_display_name` is now optional.
- **Artifact Registry now deletes tagged images** older than 90 days beyond the 20
  most recent. Previously it kept every SHA-tagged image forever. Nothing to do,
  but expect the first cleanup run to remove old images.
- **Resources in `infrastructure/` now depend on the enabled APIs.** No state
  change; the plan may reorder creation on a fresh project.

## 9. Update the workflow files

The GitHub Actions workflows gained a `checks` job, `concurrency` groups and the
`TF_CLI_ARGS_plan` env var. Easiest path: take the new versions wholesale, then
re-run `sbin/bootstrap` to fill in your `workload_identity_provider` and service
account emails from `terraform output`.

## 10. Then

```bash
sbin/check          # fmt, validate, tflint, tfsec -- no credentials needed
sbin/tf-plan        # read this carefully
terraform apply     # as an admin principal, see step 7
```

Once every repo using this template has applied successfully, the `moved` blocks
in `infrastructure/moved.tf` and `modules/cloud-workflow/moved.tf` can be
deleted.
