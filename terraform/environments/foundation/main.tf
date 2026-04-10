data "google_project" "dev" {
  project_id = var.dev_project_id
}

data "google_project" "prod" {
  project_id = var.prod_project_id
}

module "gh_oidc_dev" {
  source              = "terraform-google-modules/github-actions-runners/google//modules/gh-oidc"
  version             = "~> 5.0"
  project_id          = var.dev_project_id
  pool_id             = "github-pool"
  provider_id         = "github-provider"
  attribute_condition = "assertion.repository == 'Verggy/gcp-k8s-platform'"
  sa_mapping = {
    "terraform" = {
      sa_name   = "projects/${var.dev_project_id}/serviceAccounts/terraform@${var.dev_project_id}.iam.gserviceaccount.com"
      attribute = "attribute.repository/Verggy/gcp-k8s-platform"
    }
  }
}

resource "google_service_account_iam_member" "github_token_creator_dev" {
  service_account_id = "projects/${var.dev_project_id}/serviceAccounts/terraform@${var.dev_project_id}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.dev.number}/locations/global/workloadIdentityPools/github-pool/attribute.repository/Verggy/gcp-k8s-platform"
  depends_on         = [module.gh_oidc_dev]
}

module "gh_oidc_prod" {
  source              = "terraform-google-modules/github-actions-runners/google//modules/gh-oidc"
  version             = "~> 5.0"
  project_id          = var.prod_project_id
  pool_id             = "github-pool"
  provider_id         = "github-provider"
  attribute_condition = "assertion.repository == 'Verggy/gcp-k8s-platform'"
  sa_mapping = {
    "terraform" = {
      sa_name   = "projects/${var.prod_project_id}/serviceAccounts/terraform@${var.prod_project_id}.iam.gserviceaccount.com"
      attribute = "attribute.repository/Verggy/gcp-k8s-platform"
    }
  }
}

resource "google_service_account_iam_member" "github_token_creator_prod" {
  service_account_id = "projects/${var.prod_project_id}/serviceAccounts/terraform@${var.prod_project_id}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.prod.number}/locations/global/workloadIdentityPools/github-pool/attribute.repository/Verggy/gcp-k8s-platform"
  depends_on         = [module.gh_oidc_prod]
}
