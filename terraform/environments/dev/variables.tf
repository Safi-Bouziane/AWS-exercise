variable "aws_region" {
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  type        = string
  default     = "greenfield-dev"
}

variable "cluster_version" {
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "node_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_port" {
  description = "Fixed NodePort the app is exposed on across all worker nodes. Must be in the 30000-32767 range."
  type        = number
  default     = 30080
}

variable "app_image" {
  description = "Container image for the greenfield-project app."
  type        = string
  default = "654654510727.dkr.ecr.eu-west-1.amazonaws.com/greenfield-dev-app:1.0.0"
}