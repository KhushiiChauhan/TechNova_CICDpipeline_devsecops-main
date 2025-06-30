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