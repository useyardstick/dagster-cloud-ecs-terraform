terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_cloudwatch_log_group" "agent_log_group" {
  retention_in_days = 7
}

resource "aws_ecs_cluster" "agent_cluster" {
  name = "Dagster-Cloud-${var.dagster_organization}-${var.dagster_deployment}-Cluster"
}

resource "aws_ecs_cluster_capacity_providers" "capacity_providers" {
  cluster_name       = aws_ecs_cluster.agent_cluster.name
  capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy {
    weight            = 1
    capacity_provider = "FARGATE"
  }
}

resource "aws_vpc" "agent_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.agent_vpc.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.agent_vpc.id
  tags = {
    Name = "Public"
  }
}

resource "aws_route" "route_to_gateway" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

resource "aws_subnet" "agent_subnet" {
  vpc_id                  = aws_vpc.agent_vpc.id
  cidr_block              = "10.0.0.0/16"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
}

resource "aws_route_table_association" "public_subnet_route_table_association" {
  subnet_id      = aws_subnet.agent_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

/* AgentCluster seems to appear twice in the CloudFormation
   file. See lines 47-66 and 108-116, Skipping second one. */

resource "aws_ecs_task_definition" "agent_task_definition" {
  family = "agent_task_definition"
  cpu    = 256
  memory = 512
  container_definitions = jsonencode([
    {
      name  = "DagsterAgent"
      image = "docker.io/dagster/dagster-cloud-agent"
      environment = [{
        name  = "DAGSTER_HOME"
        value = "/opt/dagster/dagster_home"
      }]
      entryPoint  = ["bash", "-c"]
      stopTimeout = 120
      command = [<<EOS
      /bin/bash -c "mkdir -p $DAGSTER_HOME && echo '
                instance_class:
                  module: dagster_cloud
                  class: DagsterCloudAgentInstance

                dagster_cloud_api:
                  url: \"https://${var.dagster_organization}.agent.dagster.cloud\"
                  agent_token: \"${var.agent_token}\"
                  deployment: ${var.dagster_deployment}
                  
                user_code_launcher:
                  module: dagster_cloud.workspace.ecs
                  class: EcsUserCodeLauncher
                  config:
                    cluster: ${aws_ecs_cluster.agent_cluster.id}
                    subnets: [${aws_subnet.agent_subnet.id}]
                    service_discovery_namespace_id: ${aws_service_discovery_private_dns_namespace.service_discovery_namespace.id}
                    execution_role_arn: ${aws_iam_role.task_execution_role.arn}
                    task_role_arn: ${aws_iam_role.agent_role.arn}
                    log_group: ${aws_cloudwatch_log_group.agent_log_group.id}
                ' > $DAGSTER_HOME/dagster.yaml && cat $DAGSTER_HOME/dagster.yaml && dagster-cloud agent run"
      EOS
      ]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.agent_log_group.id
          awslogs-region        = var.region
          awslogs-stream-prefix = "agent"
        }
      }
    }
  ])
  execution_role_arn       = aws_iam_role.task_execution_role.arn
  task_role_arn            = aws_iam_role.agent_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
}

resource "aws_ecs_service" "agent_service" {
  # TODO: add IAM to dependencies
  name = "agent_service"
  depends_on = [
    aws_route_table_association.public_subnet_route_table_association,
    aws_route.route_to_gateway
  ]
  cluster         = aws_ecs_cluster.agent_cluster.id
  desired_count   = 1
  launch_type     = "FARGATE"
  task_definition = aws_ecs_task_definition.agent_task_definition.arn
  network_configuration {
    subnets          = [aws_subnet.agent_subnet.id]
    assign_public_ip = true
  }
}

/* todo 
    - re-add the UUID logic dropped frmo line 198
    - figure out how to add the TTL from properties; currently
      terraform considers the properties address unsupported
 */
resource "aws_service_discovery_private_dns_namespace" "service_discovery_namespace" {
  vpc  = aws_vpc.agent_vpc.id
  name = "dagster-agent-${var.dagster_organization}-${var.dagster_deployment}.local"
}

resource "aws_iam_role" "task_execution_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
  path                = "/"
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
}

resource "aws_iam_role" "agent_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
  path = "/"
  inline_policy {
    name = "root"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ec2:DescribeNetworkInterfaces",
            "ec2:DescribeRouteTables",
            "ecs:CreateService",
            "ecs:DeleteService",
            "ecs:DescribeServices",
            "ecs:DescribeTaskDefinition",
            "ecs:DescribeTasks",
            "ecs:ListAccountSettings",
            "ecs:ListServices",
            "ecs:ListTagsForResource",
            "ecs:ListTasks",
            "ecs:RegisterTaskDefinition",
            "ecs:RunTask",
            "ecs:TagResource",
            "ecs:UpdateService",
            "iam:PassRole",
            "logs:GetLogEvents",
            "secretsmanager:DescribeSecret",
            "secretsmanager:GetSecretValue",
            "secretsmanager:ListSecrets",
            "servicediscovery:CreateService",
            "servicediscovery:DeleteService",
            "servicediscovery:ListServices",
            "servicediscovery:GetNamespace",
            "servicediscovery:ListTagsForResource",
          "servicediscovery:TagResource"]
          Resource = "*"
        },
      ]
    })
  }
}
