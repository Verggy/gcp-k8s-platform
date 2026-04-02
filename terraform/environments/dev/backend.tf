terraform {
  backend "gcs" {
    bucket = "tf-state-9e3a8c0f"
    prefix = "dev"
  }
}
