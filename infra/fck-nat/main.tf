terraform {
  backend "s3" {
    bucket         = "wiktorkowalski-terraform-state"
    key            = "eks-terraform/fck-nat/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "wiktorkowalski-terraform-state"
    encrypt        = false
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.87.0"
    }
  }
}

provider "aws" {
  region  = "eu-west-1"
  profile = "wiktorkowalski"
}
