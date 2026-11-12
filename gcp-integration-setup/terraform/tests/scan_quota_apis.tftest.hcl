mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "123456789012"
    }
  }
  mock_resource "google_service_account" {
    defaults = {
      email = "nullify-cloud-connector@acme-security.iam.gserviceaccount.com"
    }
  }
}

variables {
  customer_name           = "acme"
  host_project_id         = "acme-security"
  scope                   = "projects"
  project_ids             = ["acme-security"]
  nullify_oidc_issuer_uri = "https://gcp.nullify.ai"
  nullify_tenant_id       = "GitHub-12345"
}

run "manage_scanner_apis_by_default" {
  command = plan
  assert {
    condition = output.managed_scan_quota_apis == tolist([
      "accesscontextmanager.googleapis.com",
      "bigquery.googleapis.com",
      "cloudkms.googleapis.com",
      "dataflow.googleapis.com",
      "orgpolicy.googleapis.com",
      "spanner.googleapis.com",
      "sqladmin.googleapis.com",
    ])
    error_message = "The supplied root configuration must manage all seven scanner APIs by default."
  }
}

run "root_opt_out_manages_no_scanner_apis" {
  command = plan
  variables {
    enable_scan_quota_apis = false
  }
  assert {
    condition     = length(output.managed_scan_quota_apis) == 0
    error_message = "The root opt-out must reach the nested module so restricted projects can manage scanner APIs separately."
  }
}
