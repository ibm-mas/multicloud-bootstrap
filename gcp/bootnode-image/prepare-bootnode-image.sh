#!/bin/bash
set -e

# This script should be executed on the Ubuntu instance before creating image from it.
# The created image will be used to create Bootnode instance for MAS provisioning.

# Update the package database
apt-get update

## Install pre-reqs
apt -y install apache2-utils nfs-common openjdk-8-jre-headless python3-pip skopeo
ln -s --force /usr/bin/python3 /usr/bin/python
pip3 install dotmap jaydebeapi jmespath pyyaml yq

## Install jq
wget "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
mv jq-linux64 jq
chmod +x jq
mv jq /usr/local/bin

## Download Openshift CLI and move to /usr/local/bin
wget "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.10.35/openshift-client-linux-4.10.35.tar.gz"
tar -xvf openshift-client-linux-4.10.35.tar.gz
chmod u+x oc kubectl
mv oc /usr/local/bin
mv kubectl /usr/local/bin
oc version
rm -rf openshift-client-linux-4.10.35.tar.gz

## Install Ansible
pip3 install ansible==4.9.0
pip3 install openshift
ansible-galaxy collection install community.kubernetes

# Install Ops agent and create config file
cd /tmp
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install
service google-cloud-ops-agent stop
cat <<EOT > /etc/google-cloud-ops-agent/config.yaml
logging:
  receivers:
    masocp_deployment_receiver_[UNIQID]:
      type: files
      include_paths: [/root/ansible-devops/multicloud-bootstrap/mas-provisioning.log,/root/openshift-install/config/masocp-[UNIQID]/.openshift_install.log]
      record_log_file_path: true
  service:
    pipelines:
      masocp_deployment_pipeline_[UNIQID]:
        receivers:
        - masocp_deployment_receiver_[UNIQID]
EOT

# Remove the SSH keys
rm -rf /home/*/.ssh/authorized_keys /root/.ssh/authorized_keys

echo "Bootnode preparation completed"
