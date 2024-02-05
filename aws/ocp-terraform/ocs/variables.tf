variable "region" {
  type = string
}

variable "openshift_api" {
  type = string
}

variable "openshift_username" {
  type = string
}

variable "openshift_password" {
  type = string
}

variable "openshift_token" {
  type        = string
  description = "For cases where you don't have the password but a token can be generated (e.g SSO is being used)"
  sensitive = true
}

variable "installer_workspace" {
  type        = string
  description = "Folder to store/find the installation files"
}

variable "aws_amis" {
  default = {
	"us-gov-east-1": {
        "hvm": "ami-06c66dc527ec78588"
    },
    "us-gov-west-1": {
        "hvm": "ami-006b4b58e4b6ea862"
    }
  }
}

variable "ocs" {
  default = {
    enable = true
    ami_id = ""
    dedicated_nodes = true
    dedicated_node_instance_type = "m5.4xlarge"
    dedicated_node_zones = []
    dedicated_node_subnet_ids = []
  }
}
