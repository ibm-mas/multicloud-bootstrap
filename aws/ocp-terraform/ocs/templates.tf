data "template_file" "ocs_ibm_catalog" {
  template = <<EOF
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: IBM Operator Catalog
  publisher: IBM
  sourceType: grpc
  image: icr.io/cpopen/ibm-maximo-operator-catalog:v9-240625-amd64
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
}

data "template_file" "ocs_olm" {
  template = <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
  name: openshift-storage
spec: {}
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-storage-operatorgroup
  namespace: openshift-storage
spec:
  targetNamespaces:
  - openshift-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: odf-operator
  namespace: openshift-storage
  labels:
    operators.coreos.com/odf-operator.openshift-storage: ''
spec:
  channel: "stable-4.14"
  installPlanApproval: Automatic
  name: odf-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
---
apiVersion: odf.openshift.io/v1alpha1
kind: StorageSystem
metadata:
  name: ocs-storagecluster-storagesystem
  namespace: openshift-storage
spec:
  kind: storagecluster.ocs.openshift.io/v1
  name: ocs-storagecluster
  namespace: openshift-storage
EOF
}

data "template_file" "ocs_ibm_spectrum_olm" {
  template = <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: ibm-spectrum-fusion-ns
spec: {}
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-spectrum-fusion-ns-opgroup
  namespace: ibm-spectrum-fusion-ns
spec:
  targetNamespaces:
  - ibm-spectrum-fusion-ns
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/isf-operator.ibm-spectrum-fusion-ns: ''
  name: isf-operator
  namespace: ibm-spectrum-fusion-ns
spec:
  channel: v2.0
  installPlanApproval: Automatic
  name: isf-operator
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF
}

data "template_file" "ocs_gp2_storage_class" {
  template = <<EOF
---
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: gp2
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/aws-ebs
parameters:
  encrypted: "true"
  type: gp2
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
EOF
}

data "template_file" "ocs_storagecluster" {
  template = <<EOF
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  annotations:
    cluster.ocs.openshift.io/local-devices: 'true'
    uninstall.ocs.openshift.io/cleanup-policy: delete
    uninstall.ocs.openshift.io/mode: graceful
  name: ocs-storagecluster
  namespace: openshift-storage
  finalizers:
    - storagecluster.ocs.openshift.io
spec:
    arbiter: {}
    encryption:
      kms: {}
    externalStorage: {}
    managedResources:
      cephBlockPools: {}
      cephCluster: {}
      cephConfig: {}
      cephDashboard: {}
      cephFilesystems: {}
      cephNonResilientPools: {}
      cephObjectStoreUsers: {}
      cephObjectStores: {}
      cephToolbox: {}
    mirroring: {}
    multiCloudGateway:
      dbStorageClassName: gp2
      reconcileStrategy: standalone
EOF
}

data "template_file" "ocs_toolbox" {
  template = <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rook-ceph-tools
  namespace: openshift-storage
  labels:
    app: rook-ceph-tools
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rook-ceph-tools
  template:
    metadata:
      labels:
        app: rook-ceph-tools
    spec:
      dnsPolicy: ClusterFirstWithHostNet
      containers:
      - name: rook-ceph-tools
        image: rook/ceph:v1.1.9
        command: ["/tini"]
        args: ["-g", "--", "/usr/local/bin/toolbox.sh"]
        imagePullPolicy: IfNotPresent
        env:
          - name: ROOK_ADMIN_SECRET
            valueFrom:
              secretKeyRef:
                name: rook-ceph-mon
                key: admin-secret
        securityContext:
          privileged: true
        volumeMounts:
          - mountPath: /dev
            name: dev
          - mountPath: /sys/bus
            name: sysbus
          - mountPath: /lib/modules
            name: libmodules
          - name: mon-endpoint-volume
            mountPath: /etc/rook
      hostNetwork: true
      volumes:
        - name: dev
          hostPath:
            path: /dev
        - name: sysbus
          hostPath:
            path: /sys/bus
        - name: libmodules
          hostPath:
            path: /lib/modules
        - name: mon-endpoint-volume
          configMap:
            name: rook-ceph-mon-endpoints
            items:
            - key: data
              path: mon-endpoints
EOF
}

data "template_file" "ocs_machineset" {
  template = <<EOF
%{if var.ocs.dedicated_nodes && length(var.ocs.dedicated_node_zones) > 0}
---
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: CLUSTERID
  name: CLUSTERID-workerocs-${var.ocs.dedicated_node_zones[0]}
  namespace: openshift-machine-api
spec:
  replicas: ${length(var.ocs.dedicated_node_zones) == 1 ? 3 : 1 }
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: CLUSTERID
      machine.openshift.io/cluster-api-machineset: CLUSTERID-workerocs-${var.ocs.dedicated_node_zones[0]}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: CLUSTERID
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: CLUSTERID-workerocs-${var.ocs.dedicated_node_zones[0]}
    spec:
      taints:
      - effect: NoSchedule
        key: node.ocs.openshift.io/storage
        value: "true"
      metadata:
        labels:
          cluster.ocs.openshift.io/openshift-storage: ""
          node-role.kubernetes.io/infra: ""
          node-role.kubernetes.io/worker: ""
          role: storage-node
      providerSpec:
        value:
          ami:
            id: ${local.ocs_ami_id}
          apiVersion: awsproviderconfig.openshift.io/v1beta1
          blockDevices:
          - ebs:
              encrypted: true
              iops: 2000
              kmsKey:
                arn: "${aws_kms_key.ocs_key.arn}"
              volumeSize: 300
              volumeType: gp3
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: CLUSTERID-worker-profile
          instanceType: ${var.ocs.dedicated_node_instance_type}
          kind: AWSMachineProviderConfig
          metadata:
            creationTimestamp: null
          placement:
            region: ${var.region}
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - CLUSTERID-worker-sg
          subnet:
            id: ${var.ocs.dedicated_node_subnet_ids[0]}
          tags:
          - name: kubernetes.io/cluster/CLUSTERID
            value: owned
          userDataSecret:
            name: worker-user-data
%{endif}
%{if var.ocs.dedicated_nodes && length(var.ocs.dedicated_node_zones) > 1}
---
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: CLUSTERID
  name: CLUSTERID-workerocs-${var.ocs.dedicated_node_zones[1]}
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: CLUSTERID
      machine.openshift.io/cluster-api-machineset: CLUSTERID-workerocs-${var.ocs.dedicated_node_zones[1]}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: CLUSTERID
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: CLUSTERID-workerocs-${var.ocs.dedicated_node_zones[1]}
    spec:
      taints:
      - effect: NoSchedule
        key: node.ocs.openshift.io/storage
        value: "true"
      metadata:
        labels:
          cluster.ocs.openshift.io/openshift-storage: ""
          node-role.kubernetes.io/infra: ""
          node-role.kubernetes.io/worker: ""
          role: storage-node
      providerSpec:
        value:
          ami:
            id: ${local.ocs_ami_id}
          apiVersion: awsproviderconfig.openshift.io/v1beta1
          blockDevices:
          - ebs:
              encrypted: true
              iops: 2000
              kmsKey:
                arn: "${aws_kms_key.ocs_key.arn}"
              volumeSize: 300
              volumeType: gp3
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: CLUSTERID-worker-profile
          instanceType: ${var.ocs.dedicated_node_instance_type}
          kind: AWSMachineProviderConfig
          metadata:
            creationTimestamp: null
          placement:
            region: ${var.region}
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - CLUSTERID-worker-sg
          subnet:
            id: ${var.ocs.dedicated_node_subnet_ids[1]}
          tags:
          - name: kubernetes.io/cluster/CLUSTERID
            value: owned
          userDataSecret:
            name: worker-user-data
%{endif}
%{if var.ocs.dedicated_nodes && length(var.ocs.dedicated_node_zones) > 2}
---
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: CLUSTERID
  name: CLUSTERID-workerocs-${var.ocs.dedicated_node_zones[2]}
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: CLUSTERID
      machine.openshift.io/cluster-api-machineset: CLUSTERID-workerocs-${var.ocs.dedicated_node_zones[2]}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: CLUSTERID
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: CLUSTERID-workerocs-${var.ocs.dedicated_node_zones[2]}
    spec:
      taints:
      - effect: NoSchedule
        key: node.ocs.openshift.io/storage
        value: "true"
      metadata:
        labels:
          cluster.ocs.openshift.io/openshift-storage: ""
          node-role.kubernetes.io/infra: ""
          node-role.kubernetes.io/worker: ""
          role: storage-node
      providerSpec:
        value:
          ami:
            id: ${local.ocs_ami_id}
          apiVersion: awsproviderconfig.openshift.io/v1beta1
          blockDevices:
          - ebs:
              encrypted: true
              iops: 2000
              kmsKey:
                arn: "${aws_kms_key.ocs_key.arn}"
              volumeSize: 300
              volumeType: gp3
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: CLUSTERID-worker-profile
          instanceType: ${var.ocs.dedicated_node_instance_type}
          kind: AWSMachineProviderConfig
          metadata:
            creationTimestamp: null
          placement:
            region: ${var.region}
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - CLUSTERID-worker-sg
          subnet:
            id: ${var.ocs.dedicated_node_subnet_ids[2]}
          tags:
          - name: kubernetes.io/cluster/CLUSTERID
            value: owned
          userDataSecret:
            name: worker-user-data
---
%{endif}
EOF
}