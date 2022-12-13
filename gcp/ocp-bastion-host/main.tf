provider "google" {
    project = "${var.gcp_project}"
    region = var.region
}

# Create a firewall rule for bastion host 
resource "google_compute_firewall" "allow-bastion" {
  name    = "${var.bastion_rule_name}"
  network = "${var.vpc_name}"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["bastion"]
  }

#create bastion host in the master subnet
resource "google_compute_instance" "default" {
  name         = "${var.bastion_vm_name}"
  machine_type = "n1-standard-1"
  zone         = "${var.zone}"

  tags = ["bastion"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      
    }
    
  }

  // Local SSD disk
  scratch_disk {
    interface = "SCSI"

  }

  network_interface {
    network = "${var.vpc_name}"
    subnetwork = "${var.subnet_name}"

    access_config {
    }
  }




}