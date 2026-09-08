# Cloud Run

Every subdirectory of `cloudruns/` that contains a `terraform.yaml` becomes a
Cloud Run service. **The directory name is the service name and the image name**
— the `name:` field inside must match it.

## Add one

```bash
cp -r examples/cloudrun-basic cloudruns/my-service
sed -i '' 's/^name: .*/name: my-service/' cloudruns/my-service/terraform.yaml
```

1. Put your code and a `Dockerfile` in the folder.
2. Make sure the container listens on `$PORT` (8080 by default), on `0.0.0.0`.
3. Add a `README.md` explaining what it does.
4. Open a PR and read the plan.

Nothing outside your folder needs editing.

## How images are built

You do not build or push anything by hand:

- **On a pull request** every `cloudruns/*/Dockerfile` is built, but not pushed.
  This is only to catch a broken Dockerfile before merge, and the job holds no
  cloud credentials.
- **On merge to `main`** each image is built, pushed to Artifact Registry tagged
  with the commit SHA, and then Terraform deploys that exact tag.

Because the tag is the commit SHA, a push to `main` rolls a new revision of
every Cloud Run service, not just the one you changed. That is deliberate:
a floating tag like `latest` would leave the image string unchanged in state, so
Terraform would see no diff and silently keep serving the old code. Cloud Run
revisions are cheap and traffic shifts atomically, and every running revision is
traceable to a commit.

There is no supported way to `terraform apply` a Cloud Run service from your
laptop: the image only exists once CI has built it. `cloudrun_image_tag` has no
default for that reason. `sbin/tf-plan` passes the current commit so local plans
work; if you must run Terraform by hand, add `-var cloudrun_image_tag=<sha>`.

To opt a service out and manage its image yourself, set `image:` explicitly:

```yaml
cloud-run:
  image: us-west1-docker.pkg.dev/other-project/repo/my-service:v1.2.3
```

The build is then skipped for that service and no `Dockerfile` is required.

> The plan on a PR shows the image tagged with the **PR head** commit, while the
> apply on main uses the **merge** commit. The tag in a plan is therefore
> indicative, not exact.

## Example

```yaml
name: my-service
description: what this service does

cloud-run:
  port: 8080
  cpu: "1"
  memory: 512Mi
  concurrency: 80
  min_instances: 0
  max_instances: 10
  environment_variables:
    GCP_PROJECT: $project
  secrets:
    - key: API_TOKEN
      secret: api_token
      version: latest

cron:
  schedule: "0 * * * *"
  path: /tasks/hourly
```

Unknown keys are a **plan-time error** naming the file and the key, so a typo
can't silently deploy the wrong thing.

## Reference

### Top level

| Key | Description | Required | Default |
|---|---|---|---|
| `name` | Must equal the directory name | yes | — |
| `description` | Free text | no | null |
| `cloud-run` | The service itself | yes | — |
| `cron` | Also create a Cloud Scheduler job that calls it | no | — |

### `cloud-run`

| Key | Description | Required | Default |
|---|---|---|---|
| `image` | Deploy this image instead of building the folder's Dockerfile | no | built from Dockerfile |
| `port` | Port your container listens on; also passed as `$PORT` | no | `8080` |
| `cpu` | CPU limit, e.g. `"1"`, `"2"` | no | `"1"` |
| `memory` | Memory limit, e.g. `512Mi`, `1Gi` | no | `512Mi` |
| `cpu_idle` | `true` bills CPU only during a request | no | `true` |
| `concurrency` | Requests one instance handles at once (1–1000) | no | `80` |
| `min_instances` | Warm instances; 0 scales to zero | no | `0` |
| `max_instances` | Caps concurrency, and your bill | no | `10` |
| `request_timeout` | Seconds before a request is killed (max 3600) | no | `300` |
| `execution_environment` | `EXECUTION_ENVIRONMENT_GEN2` or `..._GEN1` | no | `GEN2` |
| `ingress` | `INGRESS_TRAFFIC_ALL`, `..._INTERNAL_ONLY`, `..._INTERNAL_LOAD_BALANCER` | no | `ALL` |
| `allow_unauthenticated` | Grant `allUsers` invoker — see warning | no | `false` |
| `deletion_protection` | Refuse to delete the service | no | `true` |
| `environment_variables` | Map of env vars; `$name` substitution applies | no | `{}` |
| `secrets` | Secrets exposed as env vars | no | `[]` |

### `cron`

| Key | Description | Required | Default |
|---|---|---|---|
| `schedule` | 5-field cron, quoted: `"0 * * * *"` | yes | — |
| `path` | Path to call, e.g. `/tasks/nightly` | no | `/` |
| `http_method` | `POST`, `GET`, … | no | `POST` |
| `time_zone` | e.g. `America/New_York` | no | `Etc/UTC` |
| `attempt_deadline` | Give up after, e.g. `320s` (max `1800s`) | no | `320s` |
| `description` | Overrides the top-level description | no | inherits |

## What you get per service

- the service, in `region` from `terraform.tfvars`
- a dedicated runtime service account `cr-<name>`, holding only
  `roles/logging.logWriter` plus `secretAccessor` on the secrets it lists
- with a `cron` block: a Cloud Scheduler job `<name>-cron` and its own service
  account `crc-<name>`, holding `run.invoker` on this one service

## Things worth knowing

> **`deletion_protection` defaults to `true`.** Deleting a service directory, or
> renaming it, will make apply fail rather than tear down a live service. Set
> `deletion_protection: false`, apply, and then remove it.

> **`allow_unauthenticated: true` grants `allUsers` the invoker role** — anyone
> on the internet can call it with no credentials. Only for public endpoints
> that verify requests themselves.

> **`ingress` is network reachability, not authorisation.** The default
> `INGRESS_TRAFFIC_ALL` means the URL is reachable from the internet, but
> callers still need `roles/run.invoker`. If a service has no external callers,
> set `INGRESS_TRAFFIC_INTERNAL_ONLY` and confirm its callers still work.

> **Bind to `0.0.0.0`, not `localhost`.** Cloud Run waits for the port to open
> before routing traffic; binding to loopback makes the deploy fail a health
> check with an unhelpful message.

## Cloud Run or a Cloud Function?

Use a **function** ([functions/](../functions/README.md)) for a single handler
with no container to maintain — it is less to learn and less to keep patched.
Use **Cloud Run** when you need a Dockerfile, a non-Python runtime, a web
framework with several routes, or control over concurrency and CPU.
