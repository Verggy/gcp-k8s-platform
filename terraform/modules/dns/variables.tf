variable "region" {
  description = "GCP region"
  type        = string
}

variable "ingress_ip_name" {
  type = string
}

variable "cloudflare_zone_id" {
  type      = string
  sensitive = true
}

variable "root_record" {
  type    = string
  default = null
}

variable "www_record" {
  type    = string
  default = null
}

variable "shop_record" {
  type    = string
  default = null
}
