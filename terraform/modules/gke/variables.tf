variable "name" {
  description = "Cluster name"
  type        = string
}

variable "region" {
  type = string
}

variable "environment" {
  description = "Infrastructure environment (e.g. PROD, pre-prod, dev)"
  type        = string
}

variable "gcp_project_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "web_total_min_node_count" {
  type = number
}

variable "web_total_max_node_count" {
  type = number
}

variable "infra_total_min_node_count" {
  type = number
}

variable "infra_total_max_node_count" {
  type = number
}
variable "web_node_machine_type" {
  type    = string
  default = "e2-small"
}

variable "infra_node_machine_type" {
  type    = string
  default = "e2-small"
}
