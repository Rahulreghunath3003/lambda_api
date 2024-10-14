# AWS Region
region = "ap-south-1"

# Tag details for fetching the EC2 instance ID
tag_key = "Name"  # Change this to the appropriate tag key you are using
tag_value = "your-instance-name-or-value"  # Replace with the actual tag value

# Labeling convention parameters
label = {
  namespace  = "cbpers"
  stage      = "dev"
  deployment = "Test"
  attributes = ["nomad"]
}

# Environment variables for the Lambda function, including CircleCI API details
env_vars = {
  CIRCLECI_API_TOKEN = "CCIPAT_4XTvqk9noRhMuZXr6Z437b_01d9991ade3aaf6463ddb5a78ab32e9a4514a8fe"  # Your CircleCI API Token
  PROJECT_SLUG       = "gh/Rahul-org/test"  # Replace with your CircleCI project slug
  #INSTANCE_ID        = "your-ec2-instance-id"  # Replace with the actual EC2 instance ID
}
