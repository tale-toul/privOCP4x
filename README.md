# PRIVATE OCP 4.3 cluster 

Create a VPC on AWS and deploy an OCP 4.3 cluster on it.

[Reference documentation](https://docs.openshift.com/container-platform/4.3/installing/installing_aws/installing-aws-private.html#installing-aws-private)

## VPC creation

Create a VPC in AWS using **terraform** to deploy a private OCP 4.3 cluster on it.

In addition to the VPC network components, a bastion host is needed to run the intallation program from it.

### Terraform installation

The installation of terraform is as simple as downloading a zip compiled binary package for your operating system and architecture from:

`https://www.terraform.io/downloads.html`

Then unzip the file:

```shell
 # unzip terraform_0.11.8_linux_amd64.zip 
Archive:  terraform_0.11.8_linux_amd64.zip
  inflating: terraform
```

Place the binary somewhere in your path:

```shell
# cp terraform /usr/local/bin
```

Check that it is working:

```shell
# terraform --version
```

#### Deploying the infrastructure via terraform

To deploy the infrastructure components run the terraform manifest, some components can be adjusted via the use of predefined variables: 

```shell
$ cd Terraform
$ terraform apply -var="subnet_count=2" -var="domain_name=olivka" -var="cluster_name=tale"
```

## Bastion setup with Ansible

To successfully deploy the cluster some elements are needed besides the AWS infrastructure created before:

* Permanent credentials for an AWS account

* An ssh key pair (Optional).- the public part of the key will be installed on every node in the cluster so that ssh connection is possible.

* A DNS base domain.- This can be a public or private domain.  A private subdomain will be created under the base domain and all DNS recrods created during installation will be created in the private subdomain 

* Pull secret.- The pull secret can be obtained [here](https://cloud.redhat.com/openshift/install)

The whole process can be automated using the ansible playbook **privsetup.yaml**, this playbook prepares de bastion host created with terraform registering it with Red Hat; copying the OCP installer and _oc_ command, and creating the install-config.yaml file generated from a template using variables created by terraform.

The template used to create the install-config.yaml configuration file uses some advance contructions:

* Regular expresion filter.- The base_dns_domain variable from terraform includes a dot (.) at the end, that has to be removed, otherwise the cluster installation fails, for that a regular expresion filter is used:


```
baseDomain: {{ base_dns_domain | regex_replace('(.*)\.$' '\\1') }}
```

* for loops.- The variable containing the values is *availability_zones*, it comes from terraform and ansible understands it as a list in its original form, except for the substitution of the equal sign for the colom:

```
availability_zones : [
  "eu-west-1a",
  "eu-west-1b",
]
```

```
{% for item in availability_zones %}
        - {{ item }}
{% endfor %}
```
* Content from another file.- The pull secret and ssh key is loaded from another file:

```
pullSecret: '{{ lookup('file', './pull-secret') }}'
```

#### Running the ansible playbook

Review the file **group_vars/all/cluster-vars** and modify the value of the variables to the requirements for the cluster:

* compute_nodes.- number of compute nodes to create
* master_nodes.- number of master nodes to create

Create a file in group_vars/all/ with the credentials of a Red Hat portal user with permission to register a host (this may not be absolutely neccessary since the playbook does not install any packages in the bastion host). An example of the contents of the file:

```
subscription_username: algol80
subscription_password: YvCohpUKjEHx
```
It is a good idea to encrypt this file with ansible-vault

Create the inventory file with the _bastion_ group and the name of the bastion host:

```
[bastion]
bastion.olivka.example.com
```
Download the pull secret from [here](https://cloud.redhat.com/openshift/install) and save in a file called pull-secret in the Ansible directory.

Before running the playbook add the ssh key used by terraform to the ssh agent:

```shell
$ ssh-add ../Terraform/ocp-ssh
```

Run the playbook:

```shell
$ ansible-playbook -vvv -i inventory privsetup.yaml --vault-id vault-id
```

## OCP cluster deployment

When the playbook finishes, ssh into the bastion host to run the cluster installation.  The installation must be executed from a host in the same VPC that was created by terraform, otherwise it will not be able to resolve the internal DNS names of the components or even access to the API entry point.

The directory privOCP4 has been created and inside that one, the directory ocp4 contains the install-config.yaml, run the cluster deployment command:

```shell
$ cd privOCP4
$ ./openshift-install create cluster --dir ocp4 --log-level=info
```
