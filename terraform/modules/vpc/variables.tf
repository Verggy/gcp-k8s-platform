variable "region" {
  description = "GCP region"
  type        = string
}

variable "vpc_name" {
  type = string
}

variable "subnet_name" {
  type = string
}

variable "router_name" {
  type = string
}

variable "nat_gateway_name" {
  type = string
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
