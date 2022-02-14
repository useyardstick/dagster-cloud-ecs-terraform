variable "region" {
  description = "The aws region where this will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "dagster_organization" {
  type        = string
  description = "Enter your organization name as it appears in the dagster.cloud subdomain, e.g. `hooli` corresponding with https://hooli.dagster.cloud/."
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]*$", var.dagster_organization))
    error_message = "Invalid org name."
  }
}

variable "dagster_deployment" {
  type        = string
  description = "Enter your deployment name, e.g. `prod` corresponding with https://hooli.dagster.cloud/prod/."
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]*$", var.dagster_deployment))
    error_message = "Invalid deployment name."
  }
}

variable "agent_token" {
  type        = string
  description = "A Dagster agent token, obtained on https://{organization}.dagster.cloud/{deployment}/cloud-settings/tokens/."
  sensitive   = true
}
