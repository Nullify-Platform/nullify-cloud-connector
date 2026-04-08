provider "google" {
  project = var.host_project_id
}

provider "google-beta" {
  project = var.host_project_id
}
