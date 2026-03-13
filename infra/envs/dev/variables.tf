variable "aws_region" { default = "us-east-1" }
variable "app_name" { default = "web-api" }
variable "environment" { default = "dev" }
variable "db_password" { sensitive = true }
variable "container_image" { default = "placeholder" }
