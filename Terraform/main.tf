#PROVIDERS
provider "aws" {
  region = var.region_name
  version = "~> 2.49"
  shared_credentials_file = "aws-credentials.ini"
}

#VARIABLES
variable "region_name" {
  description = "AWS Region where the cluster is deployed"
  type = string
  default = "eu-west-1"
}

variable "domain_name" {
  description = "Public DNS domain name" 
  type = string
  default = "tale"
}

variable "cluster_name" {
  description = "Cluster name, used to define Clusterid tag and as part of other component names"
  type = string
  default = "ocp"
}

variable "vpc_name" {
  description = "Name assigned to the VPC"
  type = string
  default = "volatil"
}

variable "subnet_count" {
  description = "Number of private and public subnets to a maximum of 3, there will be the same number of private and public subnets"
  type = number
  default = 1
}

variable "ssh-keyfile" {
  description = "Name of the file with public part of the SSH key to transfer to the EC2 instances"
  type = string
  default = "ocp-ssh.pub"
}

variable "ssh-keyname" {
  description = "Name of the key that will be imported into AWS"
  type = string
  default = "ssh-key"
}

variable "dns_domain_ID" {
  description = "Zone ID for the route 53 DNS domain that will be used for this cluster"
  type = string
  default = "Z1UPG9G4YY4YK6"
}

variable "rhel7-ami" {
  description = "AMI on which the EC2 instances are based on, depends on the region"
  type = map
  default = {
    eu-central-1   = "ami-0b5edb134b768706c"
    eu-west-1      = "ami-0404b890c57861c2d"
    eu-west-2      = "ami-0fb2dd0b481d4dc1a"
    eu-west-3      = "ami-0dc7b4dac85c15019"
    eu-north-1     = "ami-030b10a31b2b6df19"
    us-east-1      = "ami-0e9678b77e3f7cc96"
    us-east-2      = "ami-0170fc126935d44c3"
    us-west-1      = "ami-0d821453063a3c9b1"
    us-west-2      = "ami-0c2dfd42fa1fbb52c"
    sa-east-1      = "ami-09de00221562b0155"
    ap-south-1     = "ami-0ec8900bf6d32e0a8"
    ap-northeast-1 = "ami-0b355f24363d9f357"
    ap-northeast-2 = "ami-0bd7fd9221135c533"
    ap-southeast-1 = "ami-097e78d10c4722996"
    ap-southeast-2 = "ami-0f7bc77e719f87581"
    ca-central-1   = "ami-056db5ae05fa26d11"
  }
}

variable "vpc_cidr" {
  description = "Network segment for the VPC"
  type = string
  default = "172.20.0.0/16"
}

#VPC
resource "aws_vpc" "vpc" {
    cidr_block = var.vpc_cidr
    enable_dns_hostnames = true
    enable_dns_support = true

    tags = {
        Name = var.vpc_name
        Clusterid = var.cluster_name
    }
}

resource "aws_vpc_dhcp_options" "vpc-options" {
  domain_name = var.region_name == "us-east-1" ? "ec2.internal" : "${var.region_name}.compute.internal" 
  domain_name_servers  = ["AmazonProvidedDNS"] 

  tags = {
        Clusterid = var.cluster_name
  }
}

resource "aws_vpc_dhcp_options_association" "vpc-association" {
  vpc_id          = aws_vpc.vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.vpc-options.id
}

#SUBNETS
data "aws_availability_zones" "avb-zones" {
  state = "available"
}

#Public subnets
resource "aws_subnet" "subnet_pub" {
    count = var.subnet_count > 0 && var.subnet_count <= 3 ? var.subnet_count : 1
    vpc_id = aws_vpc.vpc.id
    availability_zone = data.aws_availability_zones.avb-zones.names[count.index]
    #CIDR: 172.20.0.0/20; 172.20.16.0/20; 172.20.32.0/20; 
    cidr_block = "172.20.${count.index * 16}.0/20"
    map_public_ip_on_launch = true

    tags = {
        Name = "subnet_pub.${count.index}"
        Clusterid = var.cluster_name
    }
}

#Private subnets
resource "aws_subnet" "subnet_priv" {
  count = var.subnet_count > 0 && var.subnet_count <= 3 ? var.subnet_count : 1
  vpc_id = aws_vpc.vpc.id
  availability_zone = data.aws_availability_zones.avb-zones.names[count.index]
  #CIDR: 172.20.128.0/20; 172.20.144.0/20; 172.20.160.0/20; 
  cidr_block = "172.20.${(count.index + 8) * 16}.0/20"
  map_public_ip_on_launch = false

  tags = {
      Name = "subnet_priv.${count.index}"
      Clusterid = var.cluster_name
  }
}

#S3 endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id = aws_vpc.vpc.id
  service_name = "com.amazonaws.${var.region_name}.s3"
  route_table_ids = concat(aws_route_table.rtable_priv[*].id, [aws_route_table.rtable_igw.id]) 
  vpc_endpoint_type = "Gateway"

  tags = {
      Clusterid = var.cluster_name
  }
}

#INTERNET GATEWAY
resource "aws_internet_gateway" "intergw" {
    vpc_id = aws_vpc.vpc.id

    tags = {
        Name = "intergw"
        Clusterid = var.cluster_name
    }
}

#EIPS
resource "aws_eip" "nateip" {
  count = var.subnet_count > 0 && var.subnet_count <= 3 ? var.subnet_count : 1
  vpc = true
  tags = {
      Name = "nateip.${count.index}"
      Clusterid = var.cluster_name
  }
}

resource "aws_eip" "bastion_eip" {
    vpc = true
    instance = aws_instance.tale_bastion.id

    tags = {
        Name = "bastion_eip"
        Clusterid = var.cluster_name
    }
}

#NAT GATEWAYs
resource "aws_nat_gateway" "natgw" {
    count = var.subnet_count > 0 && var.subnet_count <= 3 ? var.subnet_count : 1
    allocation_id = aws_eip.nateip[count.index].id
    subnet_id = aws_subnet.subnet_pub[count.index].id
    depends_on = [aws_internet_gateway.intergw]

    tags = {
        Name = "natgw.${count.index}"
        Clusterid = var.cluster_name
    }
}

##ROUTE TABLES
#Route table: Internet Gateway access for public subnets
resource "aws_route_table" "rtable_igw" {
    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.intergw.id
    }
    tags = {
        Name = "rtable_igw"
        Clusterid = var.cluster_name
    }
}

#Route table associations
resource "aws_route_table_association" "rtabasso_subnet_pub" {
    count = var.subnet_count > 0 && var.subnet_count <= 3 ? var.subnet_count : 1
    subnet_id = aws_subnet.subnet_pub[count.index].id
    route_table_id = aws_route_table.rtable_igw.id
}

#Route tables: Out bound Internet access for private networks
resource "aws_route_table" "rtable_priv" {
    count = var.subnet_count > 0 && var.subnet_count <= 3 ? var.subnet_count : 1
    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_nat_gateway.natgw[count.index].id
    }
    tags = {
        Name = "rtable_priv.${count.index}"
        Clusterid = var.cluster_name
    }
}

#Route table associations 
resource "aws_route_table_association" "rtabasso_nat_priv" {
    count = var.subnet_count > 0 && var.subnet_count <= 3 ? var.subnet_count : 1
    subnet_id = aws_subnet.subnet_priv[count.index].id
    route_table_id = aws_route_table.rtable_priv[count.index].id
}

#SECURITY GROUPS
resource "aws_security_group" "sg-ssh-in" {
    name = "ssh-in"
    description = "Allow ssh connections"
    vpc_id = aws_vpc.vpc.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "sg-ssh"
        Clusterid = var.cluster_name
    }
}

resource "aws_security_group" "sg-all-out" {
    name = "all-out"
    description = "Allow all outgoing traffic"
    vpc_id = aws_vpc.vpc.id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "all-out"
        Clusterid = var.cluster_name
    }
}


##EC2s
##SSH key
resource "aws_key_pair" "ssh-key" {
  key_name = var.ssh-keyname
  public_key = file("${path.module}/${var.ssh-keyfile}")
}

#Bastion host
resource "aws_instance" "tale_bastion" {
  ami = var.rhel7-ami[var.region_name]
  instance_type = "m4.large"
  subnet_id = aws_subnet.subnet_pub.0.id
  vpc_security_group_ids = [aws_security_group.sg-ssh-in.id,
                            aws_security_group.sg-all-out.id]
  key_name= aws_key_pair.ssh-key.key_name

  root_block_device {
      volume_size = 25
      delete_on_termination = true
  }

  tags = {
        Name = "bastion"
        Clusterid = var.cluster_name
  }
}

#ROUTE53 CONFIG
#Datasource for rhcee.support. route53 zone
data "aws_route53_zone" "domain" {
  zone_id = var.dns_domain_ID
}

#External hosted zone, this is a public zone because it is not associated with a VPC
resource "aws_route53_zone" "external" {
  name = "${var.domain_name}.${data.aws_route53_zone.domain.name}"

  tags = {
    Name = "external"
    Clusterid = var.cluster_name
  }
}

resource "aws_route53_record" "external-ns" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = "${var.domain_name}.${data.aws_route53_zone.domain.name}"
  type    = "NS"
  ttl     = "30"

  records = [
    "${aws_route53_zone.external.name_servers.0}",
    "${aws_route53_zone.external.name_servers.1}",
    "${aws_route53_zone.external.name_servers.2}",
    "${aws_route53_zone.external.name_servers.3}",
  ]
}

resource "aws_route53_record" "bastion" {
    zone_id = aws_route53_zone.external.zone_id
    name = "bastion"
    type = "A"
    ttl = "300"
    records =[aws_eip.bastion_eip.public_ip]
}


##OUTPUT
output "bastion_public_ip" {  
 value       = aws_instance.tale_bastion.public_ip  
 description = "The public IP address of bastion server"
}
output "base_dns_domain" {
  value     = aws_route53_zone.external.name
  description = "Base DNS domain for the OCP cluster"
}
output "bastion_dns_name" {
  value = aws_route53_record.bastion.fqdn
  description = "DNS name for bastion host"
}
output "cluster_name" {
 value = var.cluster_name
 description = "Cluser name, used for prefixing some component names like the DNS domain"
}
output "region_name" {
 value = var.region_name
 description = "AWS region where the cluster and its components will be deployed"
}
output "availability_zones" {
  value = aws_subnet.subnet_priv[*].availability_zone
  description = "Names of the availbility zones used to created the subnets"
}
output "private_subnets" {
  value = aws_subnet.subnet_priv[*].id
  description = "Names of the private subnets"
}
output "vpc_cidr" {
  value = var.vpc_cidr
  description = "Network segment for the VPC"
}
output "public_subnet_cidr_block" {
  value = aws_subnet.subnet_pub[*].cidr_block
  description = "Network segments for the public subnets"
}
output "private_subnet_cidr_block" {
  value = aws_subnet.subnet_priv[*].cidr_block
  description = "Network segments for the private subnets"
}
