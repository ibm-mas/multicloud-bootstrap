#!/bin/bash

# This script should be executed on the Red Hat 8 instance before creating AMI from it.
# The created AMI will be used to create Bootnode instance for MAS provisioning.
# Parameters:
#  All parameters are positional parameters, so it is must to pass values for each parameter.
#  Either pass the actual value or pass '' to the parameter.
#   ANSIBLE_COLLECTION_VERSION: If you want to build the image with specific Ansible collection, provide that value. This is normally
#     used when the Ansible collection version is locked for a specific release.
#   ANSIBLE_COLLECTION_BRANCH: If you want to build the image with Ansible collection locally built from a specific branch of ansible
#     devops repo, provide that value. This is normally used when you are testing the changes in the Ansible code in feature branch.
#     If you have specified value for ANSIBLE_COLLECTION_VERSION, this parameter will be ignored.
#     If you do not specify values for either ANSIBLE_COLLECTION_VERSION or ANSIBLE_COLLECTION_BRANCH, the Ansible collection will be
#     built locally from the master branch of Ansible collection repo, and installed.
#   BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH: If you want to build the image with specific bootstrap automation code tag or branch, provide that value.
#     Specific branch is normally used when testing the changes from your feature branch.
#     Specific tag is normally used when the bootstrap code is locked for a specific release.
#
set -e

ANSIBLE_COLLECTION_VERSION=$1
ANSIBLE_COLLECTION_BRANCH=$2
BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH=$3

echo "ANSIBLE_COLLECTION_VERSION=$ANSIBLE_COLLECTION_VERSION"
echo "ANSIBLE_COLLECTION_BRANCH=$ANSIBLE_COLLECTION_BRANCH"
echo "BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH=$BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH"

# Remove unnecessary packages
dnf -y remove polkit

# Update all packages to latest
dnf update -y

## Install pre-reqs
dnf install git httpd-tools java python36 unzip wget zip -y
ln -s --force /usr/bin/python3 /usr/bin/python
ln -s --force /usr/bin/pip3 /usr/bin/pip
pip3 install pyyaml
pip3 install jaydebeapi
pip3 install jmespath
pip3 install yq

# Install Azure cli
rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" | tee /etc/yum.repos.d/azure-cli.repo
dnf install azure-cli -y

# Install AzureCopy cli
wget -q https://aka.ms/downloadazcopy-v10-linux -O azcopy_linux_amd64.tar.gz
tar -xzvf azcopy_linux_amd64.tar.gz
mv -f azcopy_linux_amd64_*/azcopy /usr/sbin
rm -rf azcopy_linux_amd64*

## Install jq
wget -q "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
mv jq-linux64 jq
chmod +x jq
mv jq /usr/local/bin

# Install podman
dnf module install -y container-tools

## Download Openshift CLI and move to /usr/local/bin
wget -q "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.8.46/openshift-client-linux-4.8.46.tar.gz"
tar -xvf openshift-client-linux-4.8.46.tar.gz
chmod u+x oc kubectl
mv oc /usr/local/bin
mv kubectl /usr/local/bin
rm -rf openshift-client-linux-4.8.46.tar.gz

## Install terraform
TERRAFORM_VER=`curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest |  grep tag_name | cut -d: -f2 | tr -d \"\,\v | awk '{$1=$1};1'`
echo $TERRAFORM_VER
wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VER}/terraform_${TERRAFORM_VER}_linux_amd64.zip
unzip terraform_${TERRAFORM_VER}_linux_amd64.zip
mv terraform /usr/local/bin/
rm -rf terraform_${TERRAFORM_VER}_linux_amd64.zip

## Install Ansible
pip3 install ansible==4.9.0
pip3 install openshift
ansible-galaxy collection install community.kubernetes

# Get the ansible devops colection
if [[ $ANSIBLE_COLLECTION_VERSION != "" ]]; then
    echo "Installing the ansible collection version $ANSIBLE_COLLECTION_VERSION from Ansible Galaxy"
    ansible-galaxy collection install --force ibm.mas_devops:==${ANSIBLE_COLLECTION_VERSION}
else
    if [[ $ANSIBLE_COLLECTION_BRANCH == "" ]]; then
      echo "No ANSIBLE_COLLECTION_BRANCH is provided, using the 'master' branch"
      ANSIBLE_COLLECTION_BRANCH="master"
    fi
    echo "Pulling the ansible devops code from $ANSIBLE_COLLECTION_BRANCH branch and building the collection locally and installing"
    cd /tmp
    rm -rf ansible-devops
    git clone -b $ANSIBLE_COLLECTION_BRANCH https://github.com/ibm-mas/ansible-devops.git
    cd ansible-devops/ibm/mas_devops
    ansible-galaxy collection build
    ansible-galaxy collection install --force ibm-mas_devops-*.tar.gz
    rm -rf ansible-devops ibm-mas_devops-*.tar.gz
    rm -rf ansible-devops
fi

# Get the bootstrap github code
cd /root
rm -rf ansible-devops
mkdir -p ansible-devops
cd ansible-devops
if [[ $BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH == "" ]]; then
  echo "No BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH is provided, using the 'main' branch"
  BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH="main"
fi
echo "Cloning bootstrap automation from tag/branch $BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH"
git clone -b $BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH https://github.com/ibm-mas/multicloud-bootstrap.git
cd multicloud-bootstrap
rm -rf aws azure/bootnode-image azure/master-arm
find . -type f -name "*.sh" -exec chmod +x {} \;

# Clear bash history
echo "" > /home/azureuser/.bash_history
history -c

# Remove the SSH keys
rm -rf /home/ec2-user/.ssh/authorized_keys /root/.ssh/authorized_keys

# Deprovision the VM
waagent -deprovision+user -force

echo "Bootnode preparation completed"