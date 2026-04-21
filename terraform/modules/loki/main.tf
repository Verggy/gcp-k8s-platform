resource "google_storage_bucket" "loki_chunks" {
  name                        = "${var.gcp_project_id}-loki-chunks"
  project                     = var.gcp_project_id
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
  versioning { enabled = false }
}

resource "google_service_account" "loki" {
  account_id   = "${var.environment}-loki"
  display_name = "Loki"
  project      = var.gcp_project_id
}

resource "google_storage_bucket_iam_member" "loki" {
  bucket = google_storage_bucket.loki_chunks.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.loki.email}"
}

resource "google_service_account_iam_member" "loki_workload_identity" {
  service_account_id = google_service_account.loki.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[monitoring/loki]"
}
