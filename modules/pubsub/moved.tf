# The pull subscription became optional (count), which changes these addresses
# from `.x` to `.x[0]`. Move existing state instead of destroying and recreating.
# Safe to delete once every repo using this template has applied once.
moved {
  from = google_pubsub_subscription.subscription
  to   = google_pubsub_subscription.subscription[0]
}

moved {
  from = google_service_account.pubsub_service_account
  to   = google_service_account.pubsub_service_account[0]
}

moved {
  from = google_pubsub_subscription_iam_member.viewer
  to   = google_pubsub_subscription_iam_member.viewer[0]
}

moved {
  from = google_pubsub_subscription_iam_member.subscriber
  to   = google_pubsub_subscription_iam_member.subscriber[0]
}
