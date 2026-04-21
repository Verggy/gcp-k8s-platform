variable "gcp_project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  description = "Infrastructure environment (e.g. PROD, pre-prod, dev)"
  type        = string
}
