terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.86.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  env = terraform.workspace

  check_env = local.allowed_envs[local.env]

  allowed_envs = {
    dev  = ""
    prod = ""
  }
}

locals {
  svc_name       = "${var.app_name}-svc-${local.env}"
  container_name = "${var.app_name}-container"
}

data "aws_region" "current" {}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.app_name}-vpc-${local.env}"
  cidr = var.vpc_cidr

  azs            = var.azs
  public_subnets = var.public_subnets
}

module "alb" {
  source = "terraform-aws-modules/alb/aws"

  name    = "${var.app_name}-alb-${local.env}"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  security_group_ingress_rules = {
    http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "ip_target"
      }
    }
  }

  target_groups = {
    ip_target = {
      target_type       = "ip"
      create_attachment = false

      health_check = {
        path     = "/weather?lat=1&long=1"
        interval = 10
      }
    }
  }

  enable_deletion_protection = false
}

module "ecs_cluster" {
  source = "terraform-aws-modules/ecs/aws"

  cluster_name = "${var.app_name}-cluster-${local.env}"

  fargate_capacity_providers = {
    FARGATE = {}
  }

  cluster_settings = []

  services = {
    (local.svc_name) = {
      cpu    = var.task_resources["cpu"]
      memory = var.task_resources["memory"]

      container_definitions = {
        (local.container_name) = {
          cpu       = var.task_resources["cpu"]
          memory    = var.task_resources["memory"]
          essential = true
          image     = "${var.container_image}:${local.env}"

          readonly_root_filesystem = false

          port_mappings = [
            {
              name          = "web"
              containerPort = 80
              protocol      = "tcp"
            }
          ]
        }
      }

      subnet_ids = module.vpc.public_subnets

      assign_public_ip = true

      enable_autoscaling = local.env == "prod"

      load_balancer = {
        service = {
          target_group_arn = module.alb.target_groups["ip_target"].arn
          container_name   = local.container_name
          container_port   = 80
        }
      }

      security_group_rules = {
        ingress_http = {
          type                     = "ingress"
          from_port                = 80
          to_port                  = 80
          protocol                 = "tcp"
          source_security_group_id = module.alb.security_group_id
        }
        egress_all = {
          type        = "egress"
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          cidr_blocks = ["0.0.0.0/0"]
        }
      }
    }
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  count = local.env == "prod" ? 1 : 0

  dashboard_name = "${var.app_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            [
              "AWS/ECS",
              "CPUUtilization",
              "ServiceName",
              local.svc_name,
              "ClusterName",
              module.ecs_cluster.cluster_name
            ]
          ]
          period = 60
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "${var.app_name} Service CPU Usage"
        }
      }
    ]
  })
}
