#!/bin/bash
set -e

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

ANSIBLE_COLLECTION_VERSION=$1
ANSIBLE_COLLECTION_BRANCH=$2
BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH=$3

echo "ANSIBLE_COLLECTION_VERSION=$ANSIBLE_COLLECTION_VERSION"
echo "ANSIBLE_COLLECTION_BRANCH=$ANSIBLE_COLLECTION_BRANCH"
echo "BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH=$BOOTSTRAP_AUTOMATION_TAG_OR_BRANCH"

# Remove unnecessary packages
dnf -y remove polkit

# Enable and disable repos to update certs
echo "Enable and disable repos to update certs"
#dnf update -y --disablerepo=* --enablerepo='*microsoft*' rhui-azure-rhel8-eus

# Update all packages to latest
dnf update -y

## Install pre-reqs
dnf install git httpd-tools java python39 unzip wget zip pip  container-tools -y
ln -s --force /usr/bin/python3.9 /usr/bin/python
ln -s --force /usr/bin/pip3.9 /usr/bin/pip

ln -s --force /usr/bin/python3.9 /usr/bin/python3
ln -s --force /usr/bin/pip3.9 /usr/bin/pip3

#Install openshift-install 4.12.18
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.12.18/openshift-client-linux-4.12.18.tar.gz
tar -xvf openshift-client-linux-4.12.18.tar.gz
chmod u+x oc kubectl
mv -f oc /usr/local/bin
mv -f kubectl /usr/local/bin
oc version
rm -rf openshift-client-linux-4.12.18.tar.gz

## Download the  Openshift CLI and move to /usr/local/bin
wget "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.12.18/openshift-install-linux.tar.gz"
tar -xvf openshift-install-linux.tar.gz
chmod u+x openshift-install
mv -f openshift-install /usr/local/bin
openshift-install version
rm -rf openshift-install-linux.tar.gz

# Install Azure cli for rhel9
rpm --import https://packages.microsoft.com/keys/microsoft.asc
dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
#dnf install azure-cli -y
#https://github.com/Azure/azure-cli/issues/26814
dnf install azure-cli-2.49.0-1.el9 -y

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
dnf  install -y container-tools pip


pip install --upgrade pip

pip install jaydebeapi jmespath  yq jsonpatch kubernetes  PyYAML openshift dotmap
pip install oauthlib==3.2.2

## Install terraform
TERRAFORM_VER=`curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest |  grep tag_name | cut -d: -f2 | tr -d \"\,\v | awk '{$1=$1};1'`
echo $TERRAFORM_VER
wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VER}/terraform_${TERRAFORM_VER}_linux_amd64.zip
unzip terraform_${TERRAFORM_VER}_linux_amd64.zip
mv terraform /usr/local/bin/
rm -rf terraform_${TERRAFORM_VER}_linux_amd64.zip



## Install Ansible
pip3 install ansible
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
pip install oauthlib==3.2.2
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
echo "removing folders"
rm -rf aws azure/bootnode-image azure/master-arm gcp mongo lib/ojdbc8.jar
find . -type f -name "*.sh" -exec chmod +x {} \;


#Installig cpd-cli for db2wh

wget https://github.com/IBM/cpd-cli/releases/download/v12.0.3/cpd-cli-linux-SE-12.0.3.tgz
tar -zvxf cpd-cli-linux-SE-12.0.3.tgz
rm -rf cpd-cli-linux-SE-12.0.3.tgz
cd cpd-cli-linux-SE-12.0.3-43
chmod +x cpd-cli
mv * /usr/local/bin/

# Clear bash history
echo "" > /home/azureuser/.bash_history
history -c

# Remove the SSH keys
rm -rf /home/ec2-user/.ssh/authorized_keys /root/.ssh/authorized_keys

# Deprovision the VM
waagent -deprovision+user -force

echo "Bootnode preparation completed"
