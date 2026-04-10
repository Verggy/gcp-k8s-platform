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
