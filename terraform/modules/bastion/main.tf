# -----------------------------------------------------------------------------
# Temporary Bastion Host for Database Initialization
# This creates a small EC2 instance in the public subnet that can access RDS
# Destroy this after database initialization is complete
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "project_name" {
  type = string
}

variable "region_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  type = string
}

variable "rds_security_group_id" {
  type = string
}

variable "your_ip_cidr" {
  description = "Your IP address for SSH access"
  type        = string
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for Bastion
resource "aws_security_group" "bastion" {
  name_prefix = "${var.project_name}-${var.region_name}-bastion-"
  vpc_id      = var.vpc_id
  description = "Security group for temporary bastion host"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
    description = "SSH from your IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "${var.project_name}-${var.region_name}-bastion-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Allow bastion to access RDS
resource "aws_security_group_rule" "rds_from_bastion" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = var.rds_security_group_id
  description              = "PostgreSQL from bastion"
}

# IAM Role for Bastion (to access Secrets Manager)
resource "aws_iam_role" "bastion" {
  name = "${var.project_name}-${var.region_name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.region_name}-bastion-role"
  }
}

# Policy to read Secrets Manager
resource "aws_iam_role_policy" "bastion_secrets" {
  name = "${var.project_name}-${var.region_name}-bastion-secrets"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = "arn:aws:secretsmanager:*:*:secret:${var.project_name}-*"
    }]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project_name}-${var.region_name}-bastion-profile"
  role = aws_iam_role.bastion.name
}

# Bastion EC2 Instance
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y postgresql15 jq
              
              # Create init script
              cat > /home/ec2-user/init_db.sh << 'SCRIPT'
              #!/bin/bash
              SECRET_ARN="${var.project_name}-primary-db-credentials"
              REGION="us-east-1"
              
              # Get DB credentials from Secrets Manager
              SECRET=$(aws secretsmanager get-secret-value --secret-id $SECRET_ARN --region $REGION --query 'SecretString' --output text)
              
              DB_HOST=$(echo $SECRET | jq -r '.host')
              DB_PASSWORD=$(echo $SECRET | jq -r '.password')
              DB_NAME=$(echo $SECRET | jq -r '.dbname')
              
              export PGPASSWORD=$DB_PASSWORD
              
              # Run SQL commands
              psql -h $DB_HOST -U dbadmin -d $DB_NAME << 'SQL'
              CREATE TABLE IF NOT EXISTS products (
                  id SERIAL PRIMARY KEY,
                  name VARCHAR(255) NOT NULL,
                  description TEXT,
                  price DECIMAL(10, 2) NOT NULL,
                  image_url VARCHAR(500),
                  stock INTEGER NOT NULL DEFAULT 0,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
              );

              CREATE TABLE IF NOT EXISTS orders (
                  id SERIAL PRIMARY KEY,
                  total DECIMAL(10, 2) NOT NULL,
                  status VARCHAR(50) NOT NULL,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
              );

              CREATE TABLE IF NOT EXISTS order_items (
                  id SERIAL PRIMARY KEY,
                  order_id INTEGER REFERENCES orders(id),
                  product_id INTEGER REFERENCES products(id),
                  quantity INTEGER NOT NULL,
                  price DECIMAL(10, 2) NOT NULL
              );

              INSERT INTO products (name, description, price, image_url, stock) VALUES
              ('Wireless Headphones', 'Premium noise-canceling headphones', 89.99, 'https://via.placeholder.com/300x300?text=Headphones', 50),
              ('Smart Watch', 'Fitness tracker with heart rate monitor', 199.99, 'https://via.placeholder.com/300x300?text=Smart+Watch', 30),
              ('Laptop Stand', 'Ergonomic aluminum laptop stand', 45.99, 'https://via.placeholder.com/300x300?text=Laptop+Stand', 75),
              ('USB-C Hub', '7-in-1 USB-C multiport adapter', 39.99, 'https://via.placeholder.com/300x300?text=USB-C+Hub', 100),
              ('Mechanical Keyboard', 'RGB backlit gaming keyboard', 129.99, 'https://via.placeholder.com/300x300?text=Keyboard', 40),
              ('Wireless Mouse', 'Ergonomic wireless mouse', 29.99, 'https://via.placeholder.com/300x300?text=Mouse', 80),
              ('Webcam HD', '1080p HD webcam with microphone', 69.99, 'https://via.placeholder.com/300x300?text=Webcam', 60),
              ('Phone Case', 'Protective silicone phone case', 14.99, 'https://via.placeholder.com/300x300?text=Phone+Case', 200)
              ON CONFLICT DO NOTHING;

              SELECT 'Database initialized successfully!' AS status;
              SELECT COUNT(*) AS product_count FROM products;
              SQL
              
              echo "Database initialization complete!"
              SCRIPT
              
              chmod +x /home/ec2-user/init_db.sh
              chown ec2-user:ec2-user /home/ec2-user/init_db.sh
              
              # Run the initialization
              su - ec2-user -c '/home/ec2-user/init_db.sh' > /var/log/db-init.log 2>&1
              EOF

  tags = {
    Name = "${var.project_name}-${var.region_name}-bastion"
  }
}

# Outputs
output "bastion_public_ip" {
  description = "Public IP of bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_id" {
  description = "Instance ID of bastion host"
  value       = aws_instance.bastion.id
}

output "connection_command" {
  description = "SSH command to connect to bastion"
  value       = "ssh -i your-key.pem ec2-user@${aws_instance.bastion.public_ip}"
}
