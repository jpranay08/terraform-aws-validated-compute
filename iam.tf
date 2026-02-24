# The single Role for your instances
resource "aws_iam_role" "ec2_combined_role" {
  name = "ec2-microservices-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attachment 1: SSM (for SSH access)
resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2_combined_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attachment 2: ECR (so you can pull your docker images)
resource "aws_iam_role_policy_attachment" "ecr_attach" {
  role       = aws_iam_role.ec2_combined_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# The single Profile that contains the role
resource "aws_iam_instance_profile" "combined_profile" {
  name = "ec2-combined-profile"
  role = aws_iam_role.ec2_combined_role.name
}