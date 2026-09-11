# examples/

Nothing in this directory is deployed. It exists so you can copy a working
starting point instead of writing one from a table of options.

That's deliberate: these examples used to live directly in `functions/`,
`workflows/` and `pubsubs/`, which meant a fresh clone tried to deploy all of
them on the first `terraform apply` — including secrets whose values only you
can add. A brand-new repo could not apply cleanly. Now `terraform apply` on an
untouched clone creates the base infrastructure and nothing else.

## Use one

```bash
cp -r examples/function-cron functions/my-function
```

Then rename it. **The directory name is the resource name** — the loader keys
off the folder, and the `name:` field inside `terraform.yaml` must match it. A
mismatch fails at `terraform plan` with a message telling you so.

```bash
mv functions/my-function functions/daily-report
sed -i '' 's/^name: .*/name: daily-report/' functions/daily-report/terraform.yaml
```

| Example | Copy into | What it shows |
|---|---|---|
| `function-cron` | `functions/` | A Python function on an hourly schedule, with an env var and a secret |
| `function-gh-app-token` | `functions/` | Minting a short-lived GitHub App token from secrets |
| `cloudrun-basic` | `cloudruns/` | A Flask service built from a Dockerfile, with a scheduled endpoint |
| `workflow-basic` | `workflows/` | A workflow calling a function, with no hardcoded URLs |
| `workflow-eventarc` | `workflows/` | The same, run by Eventarc whenever a message lands on `pubsub-basic`'s topic |
| `pubsub-basic` | `pubsubs/` | A topic and a pull subscription with its own service account |
| `pubsub-to-function` | `pubsubs/` | A topic that pushes every message to a function |
| `pubsub-with-sink` | `pubsubs/` | The same, plus a GCS archive of every message |

## Before you apply

Any example that references a secret needs that secret **declared** in
`terraform.tfvars` and its **value** added out of band:

```hcl
secrets = ["test_key_1"]
```

```bash
printf 'some-value' | gcloud secrets versions add test_key_1 --data-file=-
```

Referencing an undeclared secret fails at `terraform plan` with the name of the
file and the missing secret. See [secrets/readme.md](../secrets/readme.md) for
why values are handled this way.
