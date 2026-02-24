variable "aws_region" {
  default = "us-east-1"
}

variable "my_ip" {
  description = "Public IP with /32"
  type        = string
}

variable "project_name" {
  default = "devops-poc"
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}