terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.55"
    }
  }

  backend "s3" {
    # Los valores reales se pasan via backend-config al hacer init.
    # Ver terraform.tfvars.example y scripts/bootstrap-backend.sh.
    # bucket         = "spark-match-tfstate-prod"
    # key            = "prod/terraform.tfstate"
    # region         = "us-east-1"
    # use_lockfile   = true
    # encrypt        = true
  }
}