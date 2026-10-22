terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-037547369073"
    key            = "petclinic/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}
