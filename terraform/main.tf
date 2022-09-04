
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
  region  = "asia-northeast1"
  zone    = "asia-northeast1-a"
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
  region        = "asia-northeast1"
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
  config           = "regional-asia-northeast1"
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
  location_id             = "asia-northeast1-b"
  memory_size_gb          = 1
  name                    = "test-redis"
  project                 = var.project
  read_replicas_mode      = "READ_REPLICAS_DISABLED"
  redis_version           = "REDIS_6_X"
  region                  = "asia-northeast1"
  tier                    = "BASIC"
  transit_encryption_mode = "DISABLED"
}

resource "google_vpc_access_connector" "test" {
  name           = "test"
  provider       = google-beta
  region         = "asia-northeast1"
  ip_cidr_range  = "10.8.0.0/28"
  max_throughput = 300
  network        = google_compute_network.game_vpc.name
  depends_on     = [google_project_service.service]
}

resource "google_cloud_run_service" "user_api" {
  name     = "user-api"
  provider = google-beta
  location = "asia-northeast1"

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
        "run.googleapis.com/vpc-access-egress"    = "all-traffic"
      }
    }
  }
  autogenerate_revision_name = true
  depends_on                 = [google_project_service.service]
}

resource "google_cloud_run_service_iam_binding" "binding" {
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
