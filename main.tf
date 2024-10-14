terraform {
  required_version = ">= 1.5"

  # Uncomment this block to use the S3 backend for storing the Terraform state
  /*
  backend "s3" {
    bucket                  = "cb-iac-states"
    key                     = "kanjira/staging/setup/lambda/lambda.tfstate"
    region                  = "ap-southeast-1"
    shared_credentials_file = "~/.aws/credentials"
  }
  */
}

provider "aws" {
  region = var.region

  default_tags {
    tags = module.lambda_label.tags
  }
}

module "lambda_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  namespace  = var.label.namespace
  stage      = var.label.stage
  name       = var.label.deployment
  attributes = var.label.attributes
  delimiter  = "-"
}

data "aws_caller_identity" "current" {}

# Lambda execution role with policies for logging and SSM API access
resource "aws_iam_role" "lambda_exec" {
  name               = "${module.lambda_label.name}-lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = module.lambda_label.tags
}

# Policy document for Lambda permissions
data "aws_iam_policy_document" "lambda_policy_doc" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${module.lambda_label.name}-*"
    ]
  }

  statement {
    actions   = ["ssm:SendCommand", "ssm:GetCommandInvocation"]
    resources = [
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:document/AWS-RunShellScript",
      "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/${var.target_ec2_instance_id}"
    ]
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${module.lambda_label.name}-lambda-exec-policy"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_policy_doc.json
}

resource "aws_lambda_function" "nomad_job" {
  function_name = "${module.lambda_label.name}-job"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.8"

  filename         = "./function.zip"  # Path to your deployment package
  source_code_hash = filebase64sha256("function.zip")
  role             = aws_iam_role.lambda_exec.arn

  environment {
    variables = var.env_vars
  }

  tags = module.lambda_label.tags
}

# API Gateway to expose Lambda function
resource "aws_apigatewayv2_api" "lambda_api" {
  name          = "${module.lambda_label.name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.lambda_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.nomad_job.invoke_arn
}

resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "POST /invoke"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.nomad_job.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda_api.execution_arn}/*"
}

