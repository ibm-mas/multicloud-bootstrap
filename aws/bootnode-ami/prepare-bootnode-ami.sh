#!/bin/bash
set -e

# This script should be executed on the Red Hat Enterprise Linux 9 (HVM) EC2 instance before creating AMI from it.
# Once this script runs successfully, stop the EC2 instance & then create the AMI out of it.
# The created AMI will be used in CFT file to create Bootnode instance for MAS provisioning.
# Remove unnecessary packages
dnf -y remove polkit

# Update all packages to latest
dnf update -y

## Install pre-reqs
dnf install git httpd-tools java python39 unzip wget zip pip  container-tools -y
ln -s --force /usr/bin/python3.9 /usr/bin/python
ln -s --force /usr/bin/pip3.9 /usr/bin/pip

ln -s --force /usr/bin/python3.9 /usr/bin/python3
ln -s --force /usr/bin/pip3.9 /usr/bin/pip3

pip install --upgrade pip --user

pip install awscli --upgrade --user
pip install pyyaml
pip install jaydebeapi
pip install oauthlib==3.2.0
pip install pymongo

# Install AWS cli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -o awscliv2.zip
./aws/install --update
rm -rf awscliv2.zip aws

## Install jq
wget "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
mv jq-linux64 jq
chmod +x jq
mv -f jq /usr/local/bin

# Install podman
#dnf module install -y container-tools

## Download Openshift CLI and move to /usr/local/bin

#Install openshift-install 4.15.39
wget "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.15.39/openshift-client-linux.tar.gz"
tar -xvf openshift-client-linux.tar.gz
chmod u+x oc kubectl
mv -f oc /usr/local/bin
mv -f kubectl /usr/local/bin
oc version
rm -rf openshift-client-linux.tar.gz

## Install terraform
TERRAFORM_VER=`curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest |  grep tag_name | cut -d: -f2 | tr -d \"\,\v | awk '{$1=$1};1'`
echo $TERRAFORM_VER
wget https://releases.hashicorp.com/terraform/${TERRAFORM_VER}/terraform_${TERRAFORM_VER}_linux_amd64.zip
unzip terraform_${TERRAFORM_VER}_linux_amd64.zip
mv -f terraform /usr/local/bin/
terraform version
rm -rf terraform_${TERRAFORM_VER}_linux_amd64.zip

## Install Ansible
pip3 install ansible==5.7.1
pip3 install openshift
ansible-galaxy collection install community.kubernetes

# Python for Maximo Application Suite Dev/Ops
echo "Installing Python for Maximo Application Suite Dev/Ops"
pip install mas-devops

# Install CloudWatch agent
cd /tmp
wget https://s3.amazonaws.com/amazoncloudwatch-agent/redhat/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm
rm -rf amazon-cloudwatch-agent.rpm

#Installig cpd-cli for db2wh
echo "Installig cpd-cli for db2wh"
wget https://github.com/IBM/cpd-cli/releases/download/v14.0.3/cpd-cli-linux-SE-14.0.3.tgz
tar -zvxf cpd-cli-linux-SE-14.0.3.tgz
rm -rf cpd-cli-linux-SE-14.0.3.tgz
cd cpd-cli-linux-SE-14.0.3-875
chmod +x cpd-cli
mv * /usr/local/bin/


# Remove the SSH keys
rm -rf /home/ec2-user/.ssh/authorized_keys /root/.ssh/authorized_keys
echo "Bootnode preparation completed"