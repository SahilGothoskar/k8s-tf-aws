variable "region" {
  description = "The AWS region where the Kubernetes cluster will be launched"
}

provider "aws" {
  region  = var.region
  profile = "dev"
}

variable "ami" {
  type = string
}
# Retrieve the availability zones for the selected region
data "aws_availability_zones" "available" {
  state = "available"
}

# Create a VPC
resource "aws_vpc" "k8s_cluster_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "k8s-VPC"
  }
}

# Create public subnets in each availability zone
resource "aws_subnet" "public_subnets" {
  count = length(data.aws_availability_zones.available.names)

  vpc_id            = aws_vpc.k8s_cluster_vpc.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}


# Create an internet gateway
resource "aws_internet_gateway" "k8s_cluster_igw" {
  vpc_id = aws_vpc.k8s_cluster_vpc.id
  tags = {
    Name = "k8s-igw"
  }
}

# Create an public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.k8s_cluster_vpc.id

  tags = {
    Name = "k8s-public-route-table"
  }
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.k8s_cluster_igw.id
}

resource "aws_route_table_association" "public" {
  count          = length(data.aws_availability_zones.available.names)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public.id
}

# # Attach the internet gateway to the VPC
# resource "aws_internet_gateway_attachment" "k8s_cluster_igw_attachment" {
#   vpc_id              = aws_vpc.k8s_cluster_vpc.id
#   internet_gateway_id = aws_internet_gateway.k8s_cluster_igw.id
# }

# Create a security group for the instances
resource "aws_security_group" "k8_master_sg" {
  name_prefix = "K8-Master-SG"
  vpc_id      = aws_vpc.k8s_cluster_vpc.id
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "all"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "k8s-Master-SG"
  }
}

resource "aws_security_group" "k8_worker_sg" {
  name_prefix = "K8-Worker-SG"
  vpc_id      = aws_vpc.k8s_cluster_vpc.id
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "k8s-Worker-SG"
  }
}


# Launch the Kubernetes master node
resource "aws_instance" "k8s_master_instance" {
  ami                    = var.ami # Ubuntu Server 20.04 LTS
  instance_type          = "t2.medium"
  subnet_id              = aws_subnet.public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.k8_master_sg.id]
  key_name               = "SG"

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello from Kubernetes master node"
              EOF

  # Associate an Elastic IP address to the master node
  tags = {
    Name = "Kubernetes Master Node"
  }
}

resource "aws_eip" "k8s_master_eip" {
  instance = aws_instance.k8s_master_instance.id
}


# Launch the Kubernetes worker node
resource "aws_instance" "k8s_worker_instance" {
  ami                    = var.ami # Ubuntu Server 20.04 LTS
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnets[1].id
  vpc_security_group_ids = [aws_security_group.k8_worker_sg.id]
  key_name               = "SG"
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello from Kubernetes worker node"
              EOF

  # Associate an Elastic IP address to the master node
  tags = {
    Name = "Kubernetes Worker Node"
  }
}

# Define a variable to store the Kubernetes API server address
output "k8s_api_server" {
  value = aws_eip.k8s_master_eip.public_ip
}

# Define a variable to store the Kubernetes node names
output "k8s_node_names" {
  value = [aws_instance.k8s_master_instance.private_ip, aws_instance.k8s_worker_instance.private_ip]
}




