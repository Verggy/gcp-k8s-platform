variable "gcp_project_id" {
  type = string
}

variable "cloudflare_token" {
  type      = string
  sensitive = true
}

variable "environment" {
  description = "Infrastructure environment (e.g. PROD, pre-prod, dev)"
  type        = string
}
