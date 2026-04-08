resource "google_project_service" "apis" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "container.googleapis.com",
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "sts.googleapis.com"
  ])
  service            = each.key
  disable_on_destroy = false
}

module "vpc" {
  source           = "../../modules/vpc"
  vpc_name         = "dev-vpc"
  subnet_name      = "dev-subnet"
  router_name      = "dev-router"
  nat_gateway_name = "dev-nat-gateway"
  region           = var.region
  vpc_cidr         = var.vpc_cidr
  pods_cidr        = var.pods_cidr
  services_cidr    = var.services_cidr
  depends_on       = [google_project_service.apis]
}

module "gke" {
  source                     = "../../modules/gke"
  name                       = "dev-cluster"
  environment                = var.environment
  gcp_project_id             = var.gcp_project_id
  region                     = var.region
  vpc_id                     = module.vpc.vpc_id
  subnet_id                  = module.vpc.subnet_id
  web_total_min_node_count   = 1
  web_total_max_node_count   = 4
  web_node_machine_type      = "e2-medium"
  infra_total_min_node_count = 1
  infra_total_max_node_count = 3
  infra_node_machine_type    = "e2-small"
  depends_on                 = [module.vpc]
}

module "dns" {
  source             = "../../modules/dns"
  region             = var.region
  ingress_ip_name    = "dev-ingress-ip"
  cloudflare_zone_id = var.cloudflare_zone_id
  shop_record        = "dev-shop"
  depends_on         = [google_project_service.apis]
}

module "external-secrets" {
  source           = "../../modules/external-secrets"
  gcp_project_id   = var.gcp_project_id
  cloudflare_token = var.cloudflare_token
  environment      = var.environment
  depends_on       = [google_project_service.apis]
}

module "gh_oidc" {
  source              = "terraform-google-modules/github-actions-runners/google//modules/gh-oidc"
  version             = "~> 5.0"
  project_id          = var.gcp_project_id
  pool_id             = "github-pool"
  provider_id         = "github-provider"
  attribute_condition = "assertion.repository == 'Verggy/gcp-k8s-platform'"
  sa_mapping = {
    "terraform" = {
      sa_name   = "projects/${var.gcp_project_id}/serviceAccounts/terraform@${var.gcp_project_id}.iam.gserviceaccount.com"
      attribute = "attribute.repository/verggy/gcp-k8s-platform"
    }
  }
  depends_on = [google_project_service.apis]
}

data "google_project" "current" {
  project_id = var.gcp_project_id
}

resource "google_service_account_iam_member" "github_token_creator" {
  service_account_id = "projects/${var.gcp_project_id}/serviceAccounts/terraform@${var.gcp_project_id}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/github-pool/attribute.repository/Verggy/gcp-k8s-platform"
}
