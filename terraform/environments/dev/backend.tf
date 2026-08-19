terraform {
  backend "s3" {
    bucket         = "safi-exercise-tfstate"
    key            = "dev/terraform.tfstate"
    region         = "eu-west-1"
    use_lockfile = true
    encrypt        = true
    kms_key_id     = "arn:aws:kms:eu-west-1:654654510727:key/4b2dcc16-d3cb-4dc8-a48d-566c30655d16"
  }
}
