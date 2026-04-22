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

resource "random_password" "grafana_admin" {
  length  = 24
  special = true
  # exclude chars that cause shell/YAML escaping headaches
  override_special = "!@#$%^&*()-_=+[]{}"
}

resource "google_secret_manager_secret" "grafana_admin" {
  secret_id = "grafana-admin"
  project   = var.gcp_project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "grafana_admin" {
  secret = google_secret_manager_secret.grafana_admin.name
  secret_data = jsonencode({
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  })
}

resource "google_secret_manager_secret_iam_member" "eso_grafana_admin" {
  secret_id = google_secret_manager_secret.grafana_admin.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}

resource "random_password" "argocd_admin" {
  length           = 24
  special          = true
  override_special = "!@#$%^&*()-_=+[]{}"
}

resource "random_password" "argocd_server_key" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "argocd_admin" {
  secret_id = "argocd-admin"
  project   = var.gcp_project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "argocd_admin" {
  secret = google_secret_manager_secret.argocd_admin.name
  secret_data = jsonencode({
    password      = random_password.argocd_admin.result
    password-hash = bcrypt(random_password.argocd_admin.result)
    server-key    = random_password.argocd_server_key.result
  })
}

resource "google_secret_manager_secret_iam_member" "eso_argocd_admin" {
  secret_id = google_secret_manager_secret.argocd_admin.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}
