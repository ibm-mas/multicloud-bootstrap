#!/bin/bash

## Install wget, htpasswd, python3 and aws CLIs

yum install wget httpd-tools python38 -y
ln -s /usr/bin/python3 /usr/bin/python
ln -s /usr/bin/pip3 /usr/bin/pip
pip install awscli --upgrade --user
pip install pyyaml
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

## Install jq

wget "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
mv jq-linux64 jq
chmod +x jq
mv jq /usr/local/bin

## Download Openshift CLI and move to /usr/local/bin

#Install openshift-install 4.14.26
wget "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.14.26/openshift-client-linux.tar.gz"
tar -xvf openshift-client-linux.tar.gz
chmod u+x oc kubectl
mv -f oc /usr/local/bin
mv -f kubectl /usr/local/bin
oc version
rm -rf openshift-client-linux.tar.gz

## Install terraform

sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install terraform
terraform -help
