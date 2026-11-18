terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
  }
  backend "s3" {
    bucket       = "roboshop-tf-file-92"
    key          = "remote-statefile.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true

  }

}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}
