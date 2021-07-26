terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 3.51.0"
      configuration_aliases = [aws, aws.us]
    }
  }
}
