data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# creating the server with t3.micro 
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-lt"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = "devops-key"


  #adding the role created earlier
  iam_instance_profile {
    name = aws_iam_instance_profile.combined_profile.name
  }


  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = base64encode(<<-EOF
#!/bin/bash
set -e
# Redirect output to both log and console for debugging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Wait for apt lock to be released
echo "Waiting for apt lock..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done

# 1. Update and install Docker + Unzip
apt-get update -y
apt-get install -y docker.io docker-compose-v2 unzip curl

# 2. Install AWS CLI v2 (Professional way)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws

# 3. Start Docker and set permissions
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# 4. ECR Authentication (Wait 10s for IAM role to settle)
sleep 10
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "${var.account_id}.dkr.ecr.us-east-1.amazonaws.com"

# 5. Create Docker Compose file
cat <<EOT > /home/ubuntu/docker-compose.yml
services:
  service1:
    image: "${var.account_id}.dkr.ecr.us-east-1.amazonaws.com/service1:latest"
    ports:
      - "5000:5000"
    restart: always
  service2:
    image: "${var.account_id}.dkr.ecr.us-east-1.amazonaws.com/service2:latest"
    ports:
      - "5001:5001"
    restart: always
EOT

# 6. Set ownership
chown ubuntu:ubuntu /home/ubuntu/docker-compose.yml

# 7. Pull and Start
cd /home/ubuntu
docker compose pull
docker compose up -d
EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = local.common_tags
  }
}
