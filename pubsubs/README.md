# Pub/Sub

Every subdirectory of `pubsubs/` that contains a `terraform.yaml` becomes a
Pub/Sub topic — optionally with a pull subscription, push deliveries to your
functions and Cloud Run services, and a GCS archive. **The directory name is the
config name** — the `name:` field inside must match it.

## Add one

```bash
cp -r examples/pubsub-basic pubsubs/my-topic
sed -i '' 's/^name: .*/name: my-topic/' pubsubs/my-topic/terraform.yaml
```

## Example

```yaml
name: my-topic
description: what flows through this topic

pubsub:
  topic_name: my-topic

  # Push every message to a function or service (the usual pattern).
  push_to:
    - function: process-order
    - cloudrun: order-api
      path: /pubsub

  # Or, for a consumer that pulls: a subscription and an identity for it.
  subscription_id: my-subscription
  service_account_id: my-topic-sa
  ttl: "604800s"          # optional, 7 days

sink:                     # optional
  sink_name: my-archive
  retention_days: 30
```

Use `push_to` when a function or Cloud Run service should run for each message —
Pub/Sub calls it over HTTPS with an OIDC token and you write nothing but an HTTP
handler. Use `subscription_id` when something *outside* this repo pulls messages
itself. Either, both, or neither (a bare topic) is valid.

## Reference

### Top level

| Key | Description | Required | Default |
|---|---|---|---|
| `name` | Must equal the directory name | yes | — |
| `description` | Free text | no | null |
| `pubsub` | The topic and its subscription | yes | — |
| `sink` | Also archive every message to GCS | no | — |

### `pubsub` (required)

| Key | Description | Required | Default |
|---|---|---|---|
| `topic_name` | Name of the topic | yes | — |
| `push_to` | Functions / services to push each message to; see below | no | `[]` |
| `subscription_id` | Name of a pull subscription to create | no | none |
| `service_account_id` | Identity for the pull consumer. Required if `subscription_id` is set | with `subscription_id` | — |
| `service_account_display_name` | Display name for that identity | no | derived |
| `ttl` | Idle time before Pub/Sub deletes the pull subscription. **Duration string in seconds**, e.g. `"604800s"`. Omit for never. | no | never |

### `push_to` entries

| Key | Description | Required | Default |
|---|---|---|---|
| `function` | Name of a function in `functions/` | one of `function`/`cloudrun` | — |
| `cloudrun` | Name of a service in `cloudruns/` | one of `function`/`cloudrun` | — |
| `path` | Path on the target to POST to, e.g. `/pubsub` | no | root |
| `ack_deadline_seconds` | How long the handler may take before Pub/Sub redelivers | no | `60` |

The target must exist in this repo, and may appear only once per topic — two
entries for the same target from the same topic would deliver every message
twice, so it's a plan-time error; route on the message inside your handler
instead. A name that doesn't exist fails at `terraform plan` with the list of
names that do. Each target gets a dedicated push identity,
`ps-<target>`, holding invoker on that one function or service and nothing else;
topics that push to the same target share it. The handler receives a JSON body
with a base64 `message.data` — see
[examples/pubsub-to-function](../examples/pubsub-to-function/README.md).

> On projects created **before 2021-04-08**, pushes fail with 401 until you grant
> the Pub/Sub service agent `roles/iam.serviceAccountTokenCreator` on
> `ps-<target>` once by hand. The example README has the command. CI can't do
> it: the apply identity deliberately cannot set IAM on service accounts.

> `ttl` must be a duration string like `"604800s"`. An earlier version of these
> docs showed `ttl: 7`, which is not valid and fails at apply. A bad value now
> fails at plan with an explanation.

The topic is created with 7-day message retention and a storage policy pinning
messages to your `region`. The pull subscription gets a 600s ack deadline and a
10s minimum retry backoff. Every subscription this template creates — pull, push
and sink — is set to **never expire**; GCP's default would delete it after 31
idle days, which for a quiet topic means deliveries silently stop.

### `sink` (optional)

Archives **every message published to the topic** into a GCS bucket.

| Key | Description | Required | Default |
|---|---|---|---|
| `sink_name` | Bucket is created as `<project>-<sink_name>` | yes | — |
| `retention_days` | Exported files are **deleted** after this many days | no | `30` |
| `max_duration` | Start a new file after this long | no | `300s` |
| `max_bytes` | Start a new file after this many bytes | no | `10485760` |
| `filename_prefix` | Prefix for exported object names | no | `messages-` |

Two things to know:

> **`retention_days` silently deletes data.** The default drops exported
> messages after 30 days. Set it to match your actual retention obligations.

> **The sink creates a second subscription**, `<sink_name>-gcs-export`, separate
> from the one under `pubsub`. A subscription with a cloud-storage config is
> consumed by Pub/Sub itself and can't also be pulled from, so it can't share
> the pull subscription.

Earlier versions of this template created the sink bucket and nothing else — no
subscription ever wrote to it, so the bucket stayed empty. It now creates the
export subscription and grants the Pub/Sub service agent
`roles/storage.objectCreator` on the bucket.

## What you get

- the topic
- per `push_to` target: a push identity `ps-<target>` with invoker on that target
  only, and a push subscription `<topic>-to-<target>`
- with `subscription_id`: a pull subscription and a service account
  `<service_account_id>` with `pubsub.viewer` and `pubsub.subscriber` **on that
  subscription only**
- with a `sink`: a private, versionless bucket `<project>-<sink_name>` with a
  lifecycle rule, plus the export subscription

The bucket name is prefixed with your project because GCS bucket names live in
one global namespace — an unprefixed name like `example-sink` is almost
certainly already taken by someone else.
