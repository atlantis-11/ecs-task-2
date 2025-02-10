variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "app_name" {
  type    = string
  default = "weather-app"
}

variable "task_resources" {
  type = object({
    cpu    = number
    memory = number
  })
  default = {
    cpu    = 256
    memory = 512
  }
}

variable "container_image" {
  type    = string
  default = "010928206554.dkr.ecr.us-east-1.amazonaws.com/weather-app"
}
