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

variable "dns_domain_ID" {
  description = "Zone ID for the route 53 DNS domain that will be used for this cluster"
  type = string
  default = "Z0246469SRQO0B41TRDD"
}

variable "rhel-ami" {
  description = "RHEL 8 AMI on which the EC2 instances are based on, depends on the region"
  type = map
  default = {
    eu-central-1   = "ami-0f54a8b4f2be0a11e"
    eu-west-1      = "ami-0f5f1e6dd6490385e"
    eu-west-2      = "ami-0e2f4eb17efb62d46"
    eu-west-3      = "ami-00c70bf4113ead0a2"
    eu-north-1     = "ami-0b564c79c2b0f8b15"
    us-east-1      = "ami-06644055bed38ebd9"
    us-east-2      = "ami-0d871ca8a77af2948"
    us-west-1      = "ami-0032e6c1375c31695"
    us-west-2      = "ami-056b3ef335ef4f117"
    sa-east-1      = "ami-01384716b0c9ea74e"
    ap-south-1     = "ami-031711279ded7adf0"
    ap-northeast-1 = "ami-0c40556818e60c409"
    ap-northeast-2 = "ami-0eb218869d3d2d7e7"
    ap-southeast-1 = "ami-0cebc9110ef246a50"
    ap-southeast-2 = "ami-01e4b9dd23da1fa54"
    ca-central-1   = "ami-0a82febc5032feccc"
  }
}

variable "vpc_cidr" {
  description = "Network segment for the VPC"
  type = string
  default = "172.20.0.0/16"
}

variable "enable_proxy" {
  description = "If set to true, disables nat gateways and adds sg-squid security group to bastion in preparation for the use of a proxy"
  type  = bool
  default = false
}

#LOCALS
locals {
#If enable_proxy is true, the security group sg-squid is added to the list, and later applied to bastion
bastion_security_groups = var.enable_proxy ? concat([aws_security_group.sg-ssh-in.id, aws_security_group.sg-all-out.id], aws_security_group.sg-squid[*].id) : [aws_security_group.sg-ssh-in.id, aws_security_group.sg-all-out.id]

#The number of private subnets must be between 1 and 3, default is 1
private_subnet_count = var.subnet_count > 0 && var.subnet_count <= 3 ? var.subnet_count : 1

#If the proxy is enable, only 1 public subnet is created for the bastion, otherwise the same number as for the private subnets
public_subnet_count = var.enable_proxy ? 1 : local.private_subnet_count
}
