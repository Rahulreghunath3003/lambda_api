import os
import json
import boto3
import requests
import time
import logging

# Initialize clients
ssm_client = boto3.client('ssm')
ec2_client = boto3.client('ec2')

# Setup logging
logging.basicConfig(level=logging.INFO)

def lambda_handler(event, context):
    # Environment variables
    circleci_api_token = os.getenv('CIRCLECI_API_TOKEN')
    project_slug = os.getenv('PROJECT_SLUG')
    
    # Validate environment variables
    if not circleci_api_token or not project_slug:
        logging.error("Missing environment variables.")
        return {
            'statusCode': 400,
            'body': json.dumps("Missing required environment variables.")
        }
    
    # Fetch EC2 instance ID based on tags
    instance_id = get_instance_id_by_tag('Name', 'your-ec2-tag-value')  # Replace with your tag key and value
    if not instance_id:
        logging.error("No EC2 instance found with the specified tag.")
        return {
            'statusCode': 404,
            'body': json.dumps("No EC2 instance found with the specified tag.")
        }
    
    # CircleCI API endpoint for getting artifacts from the latest successful build
    circleci_url = f"https://circleci.com/api/v2/project/{project_slug}/latest/artifacts"
    headers = {
        "Circle-Token": circleci_api_token
    }
    
    try:
        # Fetch the list of artifacts
        response = requests.get(circleci_url, headers=headers, timeout=10)
        response.raise_for_status()
        artifacts = response.json().get("items", [])
        
        # Find the HCL file in artifacts
        hcl_file_url = next((artifact["url"] for artifact in artifacts if artifact["path"].endswith("file.hcl")), None)
        
        if not hcl_file_url:
            logging.error("No .hcl file found in CircleCI artifacts.")
            return {
                'statusCode': 404,
                'body': json.dumps("No .hcl file found in CircleCI artifacts.")
            }
        
        # Download the file.hcl content
        hcl_response = requests.get(hcl_file_url, headers=headers, timeout=10)
        hcl_response.raise_for_status()
        hcl_file_content = hcl_response.text
        
        # Define the SSM command
        command = "nomad run /tmp/file.hcl"
        commands = [
            "cat > /tmp/file.hcl << 'EOF'",
            hcl_file_content,
            "EOF",
            command
        ]
        
        # Send the command to the EC2 instance using SSM
        ssm_response = ssm_client.send_command(
            InstanceIds=[instance_id],
            DocumentName="AWS-RunShellScript",
            Parameters={
                "commands": commands
            }
        )
        
        # Capture the command invocation ID
        command_id = ssm_response["Command"]["CommandId"]
        
        # Check the status with retry
        max_retries = 5
        retry_delay = 5
        for attempt in range(max_retries):
            invocation_response = ssm_client.get_command_invocation(
                CommandId=command_id,
                InstanceId=instance_id
            )
            status = invocation_response["Status"]
            
            if status not in ['Pending', 'InProgress']:
                break
            time.sleep(retry_delay)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                "message": "Nomad job file executed on EC2 instance",
                "command_id": command_id,
                "command_status": status
            })
        }
    
    except requests.exceptions.RequestException as e:
        logging.error(f"Request failed: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps("Failed to retrieve the artifact from CircleCI.")
        }
    
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(str(e))
        }

def get_instance_id_by_tag(tag_key, tag_value):
    """Fetch EC2 instance ID based on a tag."""
    response = ec2_client.describe_instances(
        Filters=[
            {
                'Name': f'tag:{tag_key}',
                'Values': [Bastion-server]
            }
        ]
    )
    
    instances = [i for r in response['Reservations'] for i in r['Instances']]
    
    return instances[0]['InstanceId'] if instances else None

