#!/bin/bash
set -e

# This script should be executed on the Red Hat 8 instance before creating AMI from it.
# The created AMI will be used to create Bootnode instance for MAS provisioning.# Remove unnecessary packages# Update all packages to latest
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
wget "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.10.35/openshift-client-linux-4.10.35.tar.gz"
tar -xvf openshift-client-linux-4.10.35.tar.gz
chmod u+x oc kubectl
mv -f oc /usr/local/bin
mv -f kubectl /usr/local/bin
oc version
rm -rf openshift-client-linux-4.10.35.tar.gz



## Install terraform
TERRAFORM_VER=`curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest |  grep tag_name | cut -d: -f2 | tr -d \"\,\v | awk '{$1=$1};1'`
echo $TERRAFORM_VER
wget https://releases.hashicorp.com/terraform/${TERRAFORM_VER}/terraform_${TERRAFORM_VER}_linux_amd64.zip
unzip terraform_${TERRAFORM_VER}_linux_amd64.zip
mv -f terraform /usr/local/bin/
terraform version
rm -rf terraform_${TERRAFORM_VER}_linux_amd64.zip

## Install Ansible
pip3 install ansible==4.9.0
pip3 install openshift
ansible-galaxy collection install community.kubernetes

# Install CloudWatch agent
cd /tmp
wget https://s3.amazonaws.com/amazoncloudwatch-agent/redhat/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm
rm -rf amazon-cloudwatch-agent.rpm

# Remove the SSH keys
rm -rf /home/ec2-user/.ssh/authorized_keys /root/.ssh/authorized_keys
echo "Bootnode preparation completed"