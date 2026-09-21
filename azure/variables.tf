variable "project" {
  default = "Health-App"
}

variable "env" {
  default = "stg"
}

variable "location" {
  default = "japaneast"
}

variable "tags" {
  default = {
    owner = "unknown"
  }
}

variable "postgres_admin_user" {
  default = "pgadmin"
}

variable "postgres_admin_password" {
  default = "Password1234!"
}

variable "pg_firewall_rules" {
  default = {
    AllowAll = {
      start = "0.0.0.0"
      end   = "255.255.255.255"
    }
  }
}

variable "webapps" {
  default = {
    api = {
      node_version = "20-lts"
      always_on    = false
      https_only   = false
    }
    admin = {
      node_version = "20-lts"
      always_on    = false
      https_only   = false
    }
  }
}
