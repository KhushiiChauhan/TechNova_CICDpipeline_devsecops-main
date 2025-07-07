# --- main.tf (Final Version with S3 State Backend) ---hi khu

terraform {
  # This block tells Terraform to store its memory (state file) remotely in S3.
  # This makes your infrastructure management robust and safe to re-run.
  backend "s3" {
    bucket = "technova-tfstate-bucket-ak21357" # <-- IMPORTANT: CHANGE THIS
    key    = "technova/terraform.tfstate"       # This is the path to the state file inside the bucket.
    region = "ap-south-1"                      # The region of the bucket.
  }
}

provider "aws" {
  region = "ap-south-1" 
}

# This resource defines the firewall rules for your server.
resource "aws_security_group" "technova_sg" {
  name        = "technova-instance-sg"
  description = "Allow HTTP and SSH traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# This resource defines the EC2 virtual server itself.
resource "aws_instance" "technova_server" {
  ami           = "ami-0f5ee92e2d63afc18" 
  instance_type = "t2.micro"             
  key_name      = "technova-key" # Make sure this matches the name in your AWS Console
  vpc_security_group_ids = [aws_security_group.technova_sg.id]
  iam_instance_profile = aws_iam_instance_profile.technova_instance_profile.name

  # This script runs on the server's first boot to install Docker.
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y docker.io
              sudo systemctl start docker
              sudo systemctl enable docker
              sudo usermod -aG docker ubuntu
              EOF

  tags = {
    Name = "TechNova-Server-Terraform"  }
}




# --- Block to ADD for CloudWatch Permissions ---

resource "aws_iam_role" "technova_ec2_role" {
  name = "TechNova-EC2-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_attachment" {
  role       = aws_iam_role.technova_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "technova_instance_profile" {
  name = "TechNova-Instance-Profile"
  role = aws_iam_role.technova_ec2_role.name
}
# This resource runs a command locally on the GitHub runner AFTER the server is created.
# Its only job is to get the IP address and save it to a file for the next job to use.
resource "null_resource" "save_ip" {
  # This ensures the EC2 instance is fully created before this runs.
  depends_on = [aws_instance.technova_server]

  # This runs on the GitHub runner itself.
  provisioner "local-exec" {
    # This command writes the clean IP address into a file named ip_address.txt
    command = "echo ${aws_instance.technova_server.public_ip} > ip_address.txt"
  }
}





terraform {
  # This block tells Terraform to store its state file remotely in S3.
  backend "s3" {
    bucket = "technova-tfstate-bucket-ak21357" # <-- IMPORTANT: Use your unique S3 bucket name
    key    = "technova/terraform.tfstate"      # This is the path to the state file inside the bucket.
    region = "ap-south-1"                      # The region of the bucket.
  }
}

provider "aws" {
  region = "ap-south-1"
}

# This resource defines the firewall rules for your server.
resource "aws_security_group" "technova_sg" {
  name        = "technova-instance-sg"
  description = "Allow HTTP and SSH traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# This resource defines the EC2 virtual server itself.
resource "aws_instance" "technova_server" {
  ami                    = "ami-0f5ee92e2d63afc18"
  instance_type          = "t2.micro"
  key_name               = "technova-key" # Make sure this matches the name in your AWS Console
  vpc_security_group_ids = [aws_security_group.technova_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.technova_instance_profile.name

  # This script runs on the server's first boot to install Docker.
  user_data = <<-EOF
          #!/bin/bash
          sudo apt-get update -y
          sudo apt-get install -y docker.io
          sudo systemctl start docker
          sudo systemctl enable docker
          sudo usermod -aG docker ubuntu
          EOF

  tags = {
    Name = "TechNova-Server-Terraform"
  }
}

# --- Permissions for the EC2 instance to use CloudWatch ---
resource "aws_iam_role" "technova_ec2_role" {
  name = "TechNova-EC2-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_attachment" {
  role       = aws_iam_role.technova_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "technova_instance_profile" {
  name = "TechNova-Instance-Profile"
  role = aws_iam_role.technova_ec2_role.name
}

# ===================================================================
# --- MONITORING, ANALYSIS, AND ALERTING RESOURCES ---
# ===================================================================

# 1. SNS Topic for sending all alerts
resource "aws_sns_topic" "technova_alerts" {
  name = "TechNova-Alerts-Topic"
}

# 2. Email subscription for the SNS topic
# AWS will send a confirmation email to this address. You must click the link to activate it.
resource "aws_sns_topic_subscription" "technova_email_alerts" {
  topic_arn = aws_sns_topic.technova_alerts.arn
  protocol  = "email"
  endpoint  = "khushi2004chauhan@gmail.com" # 👈 IMPORTANT: Change this to your notification email
}

# 3. Metric Filter to count failed SSH authentications from auth.log
resource "aws_cloudwatch_log_metric_filter" "failed_auth_filter" {
  name           = "FailedAuthenticationFilter"
  pattern        = "\"Failed password\""
  log_group_name = "TechNova-Security-Auth-Logs" # This must exactly match the name in your .yml file

  metric_transformation {
    name      = "FailedLoginAttempts"
    namespace = "TechNova/Security"
    value     = "1" # Add "1" to the metric for each log event that matches
  }
}

# 4. CloudWatch Alarm that watches the "FailedLoginAttempts" metric
resource "aws_cloudwatch_alarm" "failed_auth_alarm" {
  alarm_name          = "High-Failed-Login-Attempts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = aws_cloudwatch_log_metric_filter.failed_auth_filter.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.failed_auth_filter.metric_transformation[0].namespace
  period              = "300" # 5 minutes in seconds
  statistic           = "Sum"
  threshold           = "5"   # Trigger if 5 or more failures happen in the 5 minute period
  alarm_description   = "This alarm triggers when there are 5 or more failed SSH login attempts in 5 minutes."

  # Send a notification to the SNS topic created above
  alarm_actions = [aws_sns_topic.technova_alerts.arn]
  ok_actions    = [aws_sns_topic.technova_alerts.arn] # Also notify when the alarm returns to an OK state
}