#!/bin/bash

# Copyright 2019 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

echo "Installing Azure File CSI driver, version: $driver_version ..."
kubectl apply -f rbac-csi-azurefile-controller.yaml
kubectl apply -f rbac-csi-azurefile-node.yaml
kubectl apply -f csi-azurefile-controller.yaml
kubectl apply -f csi-azurefile-driver.yaml
kubectl apply -f csi-azurefile-node.yaml
kubectl apply -f csi-azurefile-node-windows.yaml

if [[ "$#" -gt 1 ]]; then
  if [[ "$2" == *"snapshot"* ]]; then
    echo "install snapshot driver ..."
    kubectl apply -f crd-csi-snapshot.yaml
    kubectl apply -f rbac-csi-snapshot-controller.yaml
    kubectl apply -f csi-snapshot-controller.yaml
  fi
fi
echo 'Azure File CSI driver installed successfully.'
