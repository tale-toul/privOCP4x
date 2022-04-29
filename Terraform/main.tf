#PROVIDERS
provider "aws" {
  region = var.region_name
  shared_credentials_file = "aws-credentials.ini"
}

#This is only used to generate random values
provider "random" {
}

#Provides a source to create a short random string 
resource "random_string" "sufix_name" {
  length = 5
  upper = false
  special = false
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
    count = local.public_subnet_count
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
  count = local.private_subnet_count 
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

#ENDPOINTS
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

#EC2 endpoint
resource "aws_vpc_endpoint" "ec2" {
  vpc_id = aws_vpc.vpc.id
  service_name = "com.amazonaws.${var.region_name}.ec2"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true

  subnet_ids = aws_subnet.subnet_priv[*].id

  security_group_ids = [aws_security_group.sg-all-out.id, 
                        aws_security_group.sg-web-in.id]

  tags = {
      Clusterid = var.cluster_name
  }
}

#Elastic Load Balancing endpoint
resource "aws_vpc_endpoint" "elb" {
  vpc_id = aws_vpc.vpc.id
  service_name = "com.amazonaws.${var.region_name}.elasticloadbalancing"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true

  subnet_ids = aws_subnet.subnet_priv[*].id

  security_group_ids = [aws_security_group.sg-all-out.id, 
                        aws_security_group.sg-web-in.id]

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
  count = var.enable_proxy ? 0 : local.public_subnet_count
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
    count = var.enable_proxy ? 0 : local.public_subnet_count
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
    count = local.public_subnet_count
    subnet_id = aws_subnet.subnet_pub[count.index].id
    route_table_id = aws_route_table.rtable_igw.id
}

#Route tables for private subnets
resource "aws_route_table" "rtable_priv" {
    count =  local.private_subnet_count
    vpc_id = aws_vpc.vpc.id

    tags = {
        Name = "rtable_priv.${count.index}"
        Clusterid = var.cluster_name
    }
}

resource "aws_route" "internet_access" {
  count = var.enable_proxy ? 0 : local.private_subnet_count
  route_table_id = aws_route_table.rtable_priv[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.natgw[count.index].id
}

#Route table associations 
resource "aws_route_table_association" "rtabasso_nat_priv" {
    count = local.private_subnet_count
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

resource "aws_security_group" "sg-squid" {
    count = var.enable_proxy ? 1 : 0
    name = "squid"
    description = "Allow squid proxy access"
    vpc_id = aws_vpc.vpc.id

  ingress {
    from_port = 3128
    to_port = 3128
    protocol = "tcp"
    cidr_blocks = [var.vpc_cidr]
    }

    tags = {
        Name = "sg-ssh"
        Clusterid = var.cluster_name
    }
}

resource "aws_security_group" "sg-web-in" {
    name = "web-in"
    description = "Allow http and https inbound connections from anywhere"
    vpc_id = aws_vpc.vpc.id

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = [var.vpc_cidr]
    }

    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = [var.vpc_cidr]
    }

    tags = {
        Name = "sg-web-in"
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
  key_name = "ssh-key-${random_string.sufix_name.result}"
  public_key = file("${path.module}/${var.ssh_keyfile}")
}

#AMI
data "aws_ami" "rhel8" {
  most_recent = true
  owners = ["309956199498"]

  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name = "architecture"
    values = ["x86_64"]
  }

  filter {
    name = "name"
    values = ["RHEL*8.5*"]
  }
}

#Bastion host
resource "aws_instance" "tale_bastion" {
  ami = data.aws_ami.rhel8.id
  instance_type = "t3.xlarge"
  subnet_id = aws_subnet.subnet_pub.0.id
  vpc_security_group_ids = local.bastion_security_groups
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
#Datasource for route53 zone
data "aws_route53_zone" "domain" {
  zone_id = var.dns_domain_ID
}

#External hosted zone, this is a public zone because it is not associated with a VPC. 
#It is used to resolve the bastion name 
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
 description = "The public IP address of bastion host"
}
output "bastion_private_ip" {
  value     = aws_instance.tale_bastion.private_ip
  description = "The private IP address of the bastion host"
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
output "enable_proxy" {
  value = var.enable_proxy
  description = "Is the proxy enabled or not?"
}
output "ssh_keyfile" {
  value = var.ssh_keyfile
  description = "Filename containing the ssh public key injected to all nodes in the cluster, and the bastion host"
}
