variable "region" { type = string }
variable "project_name" { type = string }
variable "app_urls" { type = list(string) }
variable "google_client_id" { type = string }
variable "google_client_secret" {
  type      = string
  sensitive = true
}
variable "parser_model" { type = string }
variable "site_origin" { type = string }
variable "parser_image_uri" { type = string }

variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "route_table_ids" { type = list(string) }
variable "security_group_id" { type = string }
variable "backend_image_uri" { type = string }
variable "database_endpoint" { type = string }
variable "db_user" { type = string }
variable "db_name" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
variable "sender_email" { type = string }
variable "recipient_email" { type = string }
