variable "region" {
  description = "AWS region"
  type        = string
}

variable "target_ec2_instance_id" {
  description = "The ID of the EC2 instance to run the Nomad job file on"
  type        = string
}

variable "label" {
  description = "Naming convention parameters"
  type = object({
    namespace  = string
    stage      = string
    deployment = string
    attributes = list(string)
  })
}

variable "env_vars" {
  description = "Environment variables to pass to the Lambda function, such as CircleCI API details"
  type        = map(string)
}

