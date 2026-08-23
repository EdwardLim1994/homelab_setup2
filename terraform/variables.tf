variable "authentik_secret_key" {
  type      = string
  sensitive = true
}

variable "authentik_db_password" {
  type      = string
  sensitive = true
}

variable "gitlab_root_password" {
  type      = string
  sensitive = true
}

variable "gitlab_db_password" {
  type      = string
  sensitive = true
}
