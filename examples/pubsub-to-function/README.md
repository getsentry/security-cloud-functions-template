# pubsub-to-function

A topic that pushes every message to a Cloud Function. The most common
serverless pattern: publish a message, a function runs.

```bash
cp -r examples/pubsub-to-function pubsubs/orders
sed -i '' 's/^name: .*/name: orders/' pubsubs/orders/terraform.yaml
```

The push target (`function-cron` here) has to be a function in `functions/` or a
service in `cloudruns/`. A name that isn't fails at `terraform plan`, listing the
names that do exist.

## What Terraform creates

- the topic
- a push identity `ps-<target>` with **only** invoker on that one target — shared
  by every topic that pushes to the same target, so the name never collides
- one push subscription per topic, `<topic>-to-<target>`, delivering with an
  OIDC token for that identity

No pull subscription and no consumer service account, because nothing pulls.

## What the function receives

An HTTP POST with a JSON body:

```json
{
  "message": {
    "data": "<base64-encoded payload>",
    "messageId": "...",
    "publishTime": "...",
    "attributes": {}
  },
  "subscription": "projects/<project>/subscriptions/orders-to-function-cron"
}
```

Return any 2xx to acknowledge. Anything else — or a timeout past
`ack_deadline_seconds` — makes Pub/Sub redeliver with backoff.

## Publish a test message

```bash
gcloud pubsub topics publish orders --message='{"order_id": 42}'
```

## Older projects

Pub/Sub mints the OIDC token as its own service agent, which needs permission to
impersonate the push identity. Projects created after **2021-04-08** grant this
automatically. On an older project, pushes fail with a 401 in the subscription's
metrics until you grant it once by hand — the CI identity deliberately cannot set
IAM on service accounts:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  ps-function-cron@<project>.iam.gserviceaccount.com \
  --member=serviceAccount:service-<project-number>@gcp-sa-pubsub.iam.gserviceaccount.com \
  --role=roles/iam.serviceAccountTokenCreator
```
