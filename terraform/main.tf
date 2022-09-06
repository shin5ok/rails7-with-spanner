
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.34.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

locals {
  enable_services = toset([
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "run.googleapis.com",
    "vpcaccess.googleapis.com",
    "redis.googleapis.com",
    "spanner.googleapis.com",
  ])
}

resource "google_project_service" "compute_service" {
  service = "compute.googleapis.com"
}

resource "google_project_service" "service" {
  for_each = local.enable_services
  project  = var.project
  service  = each.value
  timeouts {
    create = "60m"
    update = "120m"
  }
  depends_on = [
    google_project_service.compute_service
  ]
}

resource "google_compute_network" "game_vpc" {
  name                    = "my-network"
  auto_create_subnetworks = true
  # mtu = 1460
  depends_on = [
    google_project_service.service
  ]
}

resource "google_compute_subnetwork" "tokyo" {
  name          = "tokyo"
  ip_cidr_range = "10.2.0.0/16"
  region        = var.region
  network       = google_compute_network.game_vpc.id
  secondary_ip_range {
    range_name    = "tokyo-ip-range"
    ip_cidr_range = "10.0.0.0/16"
  }
  depends_on = [
    google_compute_network.game_vpc
  ]
}

resource "google_secret_manager_secret" "rails_master_key" {
  project = var.project
  replication {
    automatic = true
  }
  secret_id = "RAILS_MASTER_KEY"
  depends_on = [
    google_project_service.service
  ]
}

resource "google_spanner_instance" "test_instance" {
  config           = "regional-${var.region}"
  display_name     = "test-instance"
  processing_units = 100
  labels = {
    "environment" = "development"
  }
  depends_on = [
    google_project_service.service
  ]
}

resource "google_secret_manager_secret_version" "rails_master_key_data" {
  secret      = google_secret_manager_secret.rails_master_key.id
  secret_data = var.secret_data
  depends_on = [
    google_secret_manager_secret.rails_master_key
  ]
}

resource "google_redis_instance" "test_redis" {
  authorized_network      = google_compute_network.game_vpc.id
  connect_mode            = "DIRECT_PEERING"
  location_id             = var.zone
  memory_size_gb          = 1
  name                    = "test-redis"
  project                 = var.project
  read_replicas_mode      = "READ_REPLICAS_DISABLED"
  redis_version           = "REDIS_6_X"
  region                  = var.region
  tier                    = "BASIC"
  transit_encryption_mode = "DISABLED"
}

resource "google_vpc_access_connector" "test" {
  name           = "test"
  provider       = google-beta
  region         = var.region
  ip_cidr_range  = "10.8.0.0/28"
  max_throughput = 300
  network        = google_compute_network.game_vpc.name
  depends_on     = [google_project_service.service]
}

resource "google_cloud_run_service" "user_api" {
  name     = "user-api"
  provider = google-beta
  location = var.region

  template {
    spec {
      containers {
        image = "us-docker.pkg.dev/cloudrun/container/hello"
        resources {
          limits = {
            cpu    = "1000m"
            memory = "2048M"
          }
        }
      }
      service_account_name = google_service_account.run_sa.email
    }

    metadata {
      annotations = {
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.test.id
      }
    }
  }
  autogenerate_revision_name = true
  depends_on                 = [google_project_service.service]
}

resource "google_cloud_run_service_iam_binding" "run_iam_binding" {
  location = google_cloud_run_service.user_api.location
  project  = google_cloud_run_service.user_api.project
  service  = google_cloud_run_service.user_api.name
  role     = "roles/run.invoker"
  members = [
    "allUsers",
  ]
}

resource "google_service_account" "run_sa" {
  account_id = "user-api"
}

resource "google_project_iam_member" "binding_run_sa" {
  role    = "roles/spanner.databaseUser"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
  project = var.project
}

resource "google_secret_manager_secret_iam_member" "to_run_sa" {
  project   = var.project
  secret_id = google_secret_manager_secret.rails_master_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.run_sa.email}"
}

resource "google_compute_region_network_endpoint_group" "run_neg" {
  name                  = "run-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  cloud_run {
    service = google_cloud_run_service.user_api.name
  }
  depends_on = [
    google_project_service.compute_service
  ]
}

resource "google_compute_global_address" "reserved_ip" {
  name = "reserverd-ip"
  depends_on = [
    google_project_service.compute_service
  ]
}

resource "google_compute_managed_ssl_certificate" "managed_cert" {
  provider = google-beta

  name = "managed-cert"
  managed {
    domains = ["${var.domain}"]
  }
  depends_on = [
    google_project_service.compute_service
  ]
}

resource "google_compute_backend_service" "run_backend" {
  name = "run-backend"

  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30

  backend {
    group = google_compute_region_network_endpoint_group.run_neg.id
  }
  depends_on = [
    google_project_service.compute_service
  ]
}

resource "google_compute_url_map" "run_url_map" {
  name = "run-url-map"

  default_service = google_compute_backend_service.run_backend.id
  depends_on = [
    google_project_service.compute_service
  ]
}

resource "google_compute_target_https_proxy" "run_https_proxy" {
  name = "run-https-proxy"

  url_map = google_compute_url_map.run_url_map.id
  ssl_certificates = [
    google_compute_managed_ssl_certificate.managed_cert.id
  ]
  depends_on = [
    google_project_service.compute_service
  ]
}

resource "google_compute_global_forwarding_rule" "run_lb" {
  name = "rub-lb"

  target     = google_compute_target_https_proxy.run_https_proxy.id
  port_range = "443"
  ip_address = google_compute_global_address.reserved_ip.address
  depends_on = [
    google_project_service.compute_service
  ]
}

resource "google_bigquery_dataset" "my_dataset" {
  dataset_id                  = "my_dataset"
  friendly_name               = "my_dataset"
  location                    = "US"
}

resource "google_logging_project_sink" "logging_to_bq" {
  name = "logging-to-bq"

  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.my_dataset.dataset_id}"

  filter = "resource.type=\"cloud_run_revision\" AND httpRequest.requestMethod=\"GET\""

  unique_writer_identity = true
}

resource "google_project_iam_binding" "log_writer" {
  project = var.project
  role    = "roles/bigquery.dataEditor"

  members = [
    google_logging_project_sink.logging_to_bq.writer_identity,
  ]
}
