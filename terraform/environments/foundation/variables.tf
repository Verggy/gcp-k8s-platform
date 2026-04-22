variable "dev_project_id" {
  type = string
}

variable "prod_project_id" {
  type = string
}

variable "github_repository" {
  type = string
}

variable "wif_pool_id" {
  type    = string
  default = "github-pool"
}

variable "wif_provider_id" {
  type    = string
  default = "github-provider"
}
