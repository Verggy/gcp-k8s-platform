resource "google_compute_address" "ingress_ip" {
  name   = var.ingress_ip_name
  region = var.region
}

resource "cloudflare_record" "root" {
  count   = var.root_record != null ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.root_record
  content = google_compute_address.ingress_ip.address
  type    = "A"
  ttl     = 1
  proxied = true
}

resource "cloudflare_record" "www" {
  count   = var.www_record != null ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.www_record
  content = google_compute_address.ingress_ip.address
  type    = "A"
  ttl     = 1
  proxied = true
}

resource "cloudflare_record" "shop" {
  count   = var.shop_record != null ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.shop_record
  content = google_compute_address.ingress_ip.address
  type    = "A"
  ttl     = 3600
  proxied = false
}
