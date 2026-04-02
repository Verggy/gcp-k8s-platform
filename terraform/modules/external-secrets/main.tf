 resource "google_secret_manager_secret" "cloudflare_token" {
    secret_id = "cloudflare-api-token"
    project   = var.gcp_project_id
    replication {
      auto {}
    }
  }

resource "google_secret_manager_secret_version" "cloudflare_token" {
  secret      = google_secret_manager_secret.cloudflare_token.name
  secret_data = var.cloudflare_token
}

resource "google_service_account" "eso" {
  account_id   = "${var.environment}-external-secrets-operator"
  display_name = "External Secrets Operator"
}

resource "google_secret_manager_secret_iam_member" "eso" {
  secret_id = google_secret_manager_secret.cloudflare_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}

resource "google_service_account_iam_member" "eso_workload_identity" {
  service_account_id = google_service_account.eso.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[external-secrets-operator/external-secrets-operator]"
}
