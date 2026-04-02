variable "gcp_project_id" {
  type = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-central2"
}

variable "cloudflare_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_zone_id" {
  type      = string
  sensitive = true
}

variable "environment" {
  description = "Infrastructure environment (e.g. PROD, pre-prod, dev)"
  type        = string
}

variable "vpc_cidr" {
  type = string
}

variable "pods_cidr" {
  type = string
}

variable "services_cidr" {
  type = string
}
