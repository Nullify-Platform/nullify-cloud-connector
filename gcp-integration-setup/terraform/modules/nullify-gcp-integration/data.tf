# Project lookup used by outputs.tf to compose the workload_identity_provider
# resource path. Lives in its own data.tf so reviewers don't have to find it
# at the bottom of outputs.tf.
data "google_project" "host" {
  project_id = var.host_project_id
}
