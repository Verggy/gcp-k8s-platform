resource "google_container_cluster" "main-cluster" {
  name     = var.name
  location = var.region

  network    = var.vpc_id
  subnetwork = var.subnet_id

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false # portfolio project, intentional — allows full terraform destroy for easy cleanup

  # prevents SSD quota exhaustion during bootstrap, deleted by remove_default_node_pool
  node_config {
    disk_type = "pd-standard"
  }

  cluster_autoscaling {
    enabled = false
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = false
    }
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  resource_labels = {
    env = var.environment
  }
}


resource "google_container_node_pool" "web-nodes" {
  name     = "web-node-pool"
  cluster  = google_container_cluster.main-cluster.id
  location = var.region

  autoscaling {
    location_policy      = "BALANCED"
    total_min_node_count = var.web_total_min_node_count
    total_max_node_count = var.web_total_max_node_count
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.web_node_machine_type
    disk_size_gb = 30
    disk_type    = "pd-standard" #  web-node is stateles, avoids SSD quota consumption
    spot         = true          # decided to use spot vms here as this node pool is for stateless webapp

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      env     = var.environment
      purpose = "web-node"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

resource "google_container_node_pool" "infra-nodes" {
  name     = "infra-node-pool"
  cluster  = google_container_cluster.main-cluster.id
  location = var.region

  autoscaling {
    location_policy      = "BALANCED"
    total_min_node_count = var.infra_total_min_node_count
    total_max_node_count = var.infra_total_max_node_count
  }
  node_config {
    machine_type = var.infra_node_machine_type
    disk_size_gb = 20
    disk_type    = "pd-standard"
    spot         = false # critical — no downtime is crucial

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      env     = var.environment
      purpose = "infra"
    }

    taint {
      key    = "purpose"
      value  = "infra"
      effect = "NO_SCHEDULE"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
