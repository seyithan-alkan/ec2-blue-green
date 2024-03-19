variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "vpc_name" {
  type    = string
  default = "my_vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "private_subnets" {
  default = {
    "private_subnet_1" = 1
    "private_subnet_2" = 2
    
  }
}

variable "public_subnets" {
  default = {
    "public_subnet_1" = 1
    "public_subnet_2" = 2
    
  }
}


variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "seyithanalkan.com"
}

variable "repo_name" {
  description = "The name of the repository"
  type        = string
}

variable "iis_port" {
  description = "The name of the repository"
  type        = number
}

variable "seyithan_pfx" {
  description = "The value of the seyithan-pfx secret"
  type        = string
}

variable "seyithan_pfx_secret" {
  description = "The value of the seyithan-pfx-secret"
  type        = string
}

variable "gh_action_token" {
  description = "The value of the github-action-token"
  type        = string
}

variable "ssl_certificate_arn" {
  default = "arn:aws:acm:eu-central-1:544167776152:certificate/80e0ed23-8abe-4d8c-99fc-590a4189556a"
  description = "The value of the ssl arn"
  type        = string
}