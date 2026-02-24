locals {
  common_tags = {
    Project     = var.project_name
    Environment = "dev"
    Owner       = "PranayCJasti"
    CostCenter  = "engineering"
  }
}
