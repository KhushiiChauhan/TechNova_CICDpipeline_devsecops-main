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






# --- Create CloudWatch Log Groups ---
# This ensures the log groups exist before we try to create filters for them.

resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "TechNova-App-Logs"
  retention_in_days = 7 # Optional: Automatically delete logs older than 7 days
}

resource "aws_cloudwatch_log_group" "security_auth_logs" {
  name              = "TechNova-Security-Auth-Logs"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "system_syslog" {
  name              = "TechNova-System-Syslog"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "unattended_upgrades_logs" {
  name              = "TechNova-Security-Unattended-Upgrades"
  retention_in_days = 7
}




# A variable to hold the email address for notifications
variable "notification_email" {
  description = "The email address to receive CloudWatch alerts"
  type        = string
  default     = "khushi2004chauhan@gmail.com" # Change this to your actual email
}

# Creates the SNS topic for sending alerts
resource "aws_sns_topic" "brewhaven_alerts" {
  name = "BrewHaven-Critical-Alerts"
}

# Subscribes the email address to the SNS topic
resource "aws_sns_topic_subscription" "email_target" {
  topic_arn = aws_sns_topic.brewhaven_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}




# Assumes you have your log group names defined, or you can hardcode them.
# Let's assume you have an output from another resource for the log group names.
# For simplicity, I'll hardcode them based on your YAML file.



# --- Metric Filters ---
# This section is updated to depend on the log group resources.

resource "aws_cloudwatch_log_metric_filter" "app_error_filter" {
  name           = "ApplicationErrorFilter"
  pattern        = "ERROR"
  log_group_name = aws_cloudwatch_log_group.app_logs.name  # <-- This is the corrected line

  metric_transformation {
    name      = "ErrorCount"
    namespace = "BrewHaven/Application"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "failed_login_filter" {
  name           = "FailedLoginFilter"
  pattern        = "Failed password"
  log_group_name = aws_cloudwatch_log_group.security_auth_logs.name # <-- This is the corrected line

  metric_transformation {
    name      = "FailedLoginCount"
    namespace = "BrewHaven/Security"
    value     = "1"
  }
}



# --- Anomaly Detection Alarms ---
# --- Anomaly Detection Alarms ---
# This is the final corrected version.
# --- Anomaly Detection Alarms (Final Correct Version) ---


# --- Anomaly Detection Alarms (Final Correct Version) ---

resource "aws_cloudwatch_metric_alarm" "app_error_anomaly_alarm" {
  alarm_name          = "High-Application-Error-Anomaly"
  alarm_description   = "Triggers when the application error count is anomalously high."
  alarm_actions       = [aws_sns_topic.brewhaven_alerts.arn]
  ok_actions          = [aws_sns_topic.brewhaven_alerts.arn]

  evaluation_periods  = 2
  comparison_operator = "GreaterThanUpperThreshold"
  threshold_metric_id = "e1"  # ✅ fixed

  metric_query {
    id          = "m1"
    return_data = true
    metric {
      metric_name = aws_cloudwatch_log_metric_filter.app_error_filter.metric_transformation[0].name
      namespace   = aws_cloudwatch_log_metric_filter.app_error_filter.metric_transformation[0].namespace
      period      = 300
      stat        = "Sum"
    }
  }

  metric_query {
    id          = "e1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "ErrorCount (Expected)"
    return_data = true
  }
}


resource "aws_cloudwatch_metric_alarm" "failed_login_anomaly_alarm" {
  alarm_name          = "High-Failed-Login-Anomaly"
  alarm_description   = "Triggers on an anomalous number of failed SSH logins."
  alarm_actions       = [aws_sns_topic.brewhaven_alerts.arn]
  ok_actions          = [aws_sns_topic.brewhaven_alerts.arn]

  evaluation_periods  = 2
  comparison_operator = "GreaterThanUpperThreshold"
  threshold_metric_id = "e1"  # ✅ fixed

  metric_query {
    id          = "m1"
    return_data = true
    metric {
      metric_name = aws_cloudwatch_log_metric_filter.failed_login_filter.metric_transformation[0].name
      namespace   = aws_cloudwatch_log_metric_filter.failed_login_filter.metric_transformation[0].namespace
      period      = 300
      stat        = "Sum"
    }
  }

  metric_query {
    id          = "e1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "FailedLoginCount (Expected)"
    return_data = true
  }
}

# --- Example: Standard EC2 Metric Alarm (CPU Utilization > 80%) ---
resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  alarm_name          = "High-CPU-Utilization"
  alarm_description   = "Alarm when CPU exceeds 1% for 5 minutes (test)."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 10 #<<================================time to change accoding to threashold
  statistic           = "Average"
  threshold           = 1
  alarm_actions       = [aws_sns_topic.brewhaven_alerts.arn]
  ok_actions          = [aws_sns_topic.brewhaven_alerts.arn]
  dimensions = {
    InstanceId = aws_instance.technova_server.id
  }
}
