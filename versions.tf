terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "pranaycjasti-devops-poc-terraform-state"
    key            = "dev/state.tfstate"
    region         = "us-east-1"
    dynamodb_table = "devops-poc-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
