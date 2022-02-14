# Dagster Cloud ECS via Terraform

This is one-for-one port (with minor exceptions) of the [Cloudformation template](https://s3.amazonaws.com/dagster.cloud/cloudformation/ecs-agent-vpc.yaml) provided by [Dagster](https://docs.dagster.cloud/agents/ecs/setup).

Small divergences from the original are noted inline. Also, this is my first time working with Terraform, so there may be some beginners mistakes in the code as well. Target AWS Region, along with Dagster Deployment, Dagster Organization, and Agent Token should be provided as input vars.
