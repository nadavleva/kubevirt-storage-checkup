# CSI Certification Tests Documentation

This document describes the CSI-related tests included in the KubeVirt Storage Checkup test suite, as required for [Red Hat Software Certification](http://docs.redhat.com/en/documentation/red_hat_software_certification/2025/html/red_hat_software_certification_workflow_guide/con_csi-certification_openshift-sw-cert-workflow-working-with-container-network-interface).

Related Jira: [OCPNAS-382](https://issues.redhat.com/browse/OCPNAS-382) - Locate and analyze existing CSI certification tests

---

## Prerequisites

Before running the KubeVirt Storage Checkup, ensure you have:

1. **OpenShift Cluster** with OpenShift Virtualization (CNV) installed
2. **Cluster Admin Access** to create RBAC resources
3. **kubectl/oc CLI** configured to access the cluster
4. **CSI Driver** installed and configured with a StorageClass

---

## How to Run the Test Suite

### 1. Create the Target Namespace

```bash
kubectl create namespace <target-namespace>
```

### 2. Apply Permissions

Apply the required ServiceAccount, Role, and RoleBinding:

```bash
kubectl apply -n <target-namespace> -f manifests/storage_checkup_permissions.yaml
```

Create cluster-reader permissions for the checkup ServiceAccount:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubevirt-storage-checkup-clustereader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-reader
subjects:
- kind: ServiceAccount
  name: storage-checkup-sa
  namespace: <target-namespace>
```

### 3. Run the Checkup

```bash
export CHECKUP_NAMESPACE=<target-namespace>
envsubst < manifests/storage_checkup.yaml | kubectl apply -f -
```

### 4. Retrieve Results

After the checkup Job completes:

```bash
kubectl get configmap storage-checkup-config -n <target-namespace> -o yaml
```

### 5. Cleanup

```bash
envsubst < manifests/storage_checkup.yaml | kubectl delete -f -
```

---

## Test Cases Summary

| # | Test Case | What is Validated | Result Key | Pass Criteria |
|---|-----------|-------------------|------------|---------------|
| 1 | Version Detection | OCP and CNV versions are retrievable | `ocpVersion`, `cnvVersion` | Versions reported successfully |
| 2 | Default Storage Class | A single default storage class exists | `defaultStorageClass` | Exactly one default SC configured |
| 3 | PVC Creation & Binding | CSI driver can provision and bind a PVC | `pvcBound` | PVC reaches `Bound` phase within timeout |
| 4 | Storage Profiles - ClaimPropertySets | StorageProfiles have valid ClaimPropertySets | `storageProfilesWithEmptyClaimPropertySets` | No profiles with empty ClaimPropertySets |
| 5 | Storage Profiles - Smart Clone | CSI driver supports efficient cloning | `storageProfilesWithSmartClone` | At least one profile supports CSI/snapshot clone |
| 6 | Storage Profiles - RWX | CSI driver supports ReadWriteMany | `storageProfilesWithRWX` | RWX support detected (informational) |
| 7 | VolumeSnapshotClass | VolumeSnapshotClass exists for snapshot-capable profiles | `storageProfileMissingVolumeSnapshotClass` | Matching VolumeSnapshotClass exists |
| 8 | Golden Images - DataImportCron | DataImportCrons are up to date | `goldenImagesNotUpToDate` | All DICs have `UpToDate` condition |
| 9 | Golden Images - DataSource | DataSources have valid PVC/Snapshot source | `goldenImagesNoDataSource` | All DataSources have valid source |
| 10 | VM Storage Class - RBD | VMs use virtualization-optimized RBD class | `vmsWithNonVirtRbdStorageClass` | No VMs using plain RBD when virt class exists |
| 11 | VM Storage Class - EFS | EFS storage class has uid/gid configured | `vmsWithUnsetEfsStorageClass` | No VMs using unset EFS class |
| 12 | VM Boot from Golden Image | VM can boot from cloned golden image | `vmBootFromGoldenImage` | VM boots and guest agent connects |
| 13 | Volume Clone Type | Efficient cloning (CSI/snapshot) is used | `vmVolumeClone` | Clone type is `snapshot` or `csi-clone` |
| 14 | VM Live Migration | VM can live migrate with attached storage | `vmLiveMigration` | Migration completes successfully |
| 15 | Volume Hotplug - Attach | Volume can be hot-attached to running VM | `vmHotplugVolume` | Volume reaches `Ready` state |
| 16 | Volume Hotplug - Detach | Volume can be hot-detached from running VM | `vmHotplugVolume` | Volume fully removed |
| 17 | Concurrent VM Boot | Multiple VMs can boot simultaneously | `concurrentVMBoot` | All VMs boot within timeout |

---

## CSI APIs Tested

The following table maps test cases to the underlying CSI specification APIs being exercised:

| Test Case | CSI API / Capability | Description |
|-----------|---------------------|-------------|
| PVC Creation & Binding | `CreateVolume` | Tests dynamic volume provisioning |
| PVC Creation & Binding | `ControllerPublishVolume` | Tests volume attachment to node |
| Storage Profiles - Smart Clone | `CreateVolume` (clone source) | Tests CSI volume cloning capability |
| VolumeSnapshotClass | `CreateSnapshot` | Tests CSI snapshot capability |
| VolumeSnapshotClass | `DeleteSnapshot` | Tests CSI snapshot deletion |
| VM Boot from Golden Image | `CreateVolume` (from snapshot/clone) | Tests volume creation from snapshot or clone |
| Volume Clone Type | `CreateVolume` (clone) | Tests CSI-native cloning vs host-assisted |
| VM Live Migration | `NodePublishVolume` / `NodeUnpublishVolume` | Tests RWX volume multi-attach capability |
| Volume Hotplug - Attach | `ControllerPublishVolume`, `NodeStageVolume`, `NodePublishVolume` | Tests dynamic volume attachment |
| Volume Hotplug - Detach | `ControllerUnpublishVolume`, `NodeUnstageVolume`, `NodeUnpublishVolume` | Tests dynamic volume detachment |

### CSI Capabilities Validated

| CSI Capability | How It's Tested |
|----------------|-----------------|
| `CREATE_DELETE_VOLUME` | PVC creation and cleanup |
| `CREATE_DELETE_SNAPSHOT` | Clone from snapshot, VolumeSnapshotClass validation |
| `CLONE_VOLUME` | Smart clone detection in StorageProfiles |
| `PUBLISH_UNPUBLISH_VOLUME` | VM boot, hotplug attach/detach |
| `STAGE_UNSTAGE_VOLUME` | Volume hotplug operations |
| `MULTI_NODE_MULTI_WRITER` | RWX access mode validation, live migration |

---

## Detailed Test Descriptions

### 1. Version Detection

| Aspect | Details |
|--------|---------|
| **Function** | `checkVersions` |
| **Validates** | OCP cluster version, CNV operator version |
| **CSI Relevance** | Ensures compatibility reporting |
| **Results** | `status.result.ocpVersion`, `status.result.cnvVersion` |

### 2. Default Storage Class Validation

| Aspect | Details |
|--------|---------|
| **Function** | `checkDefaultStorageClass` |
| **Validates** | Single default storage class exists |
| **Annotations Checked** | `storageclass.kubevirt.io/is-default-virt-class`, `storageclass.kubernetes.io/is-default-class` |
| **Errors** | `no default storage class`, `there are multiple default storage classes` |

### 3. PVC Creation and Binding

| Aspect | Details |
|--------|---------|
| **Function** | `checkPVCCreationAndBinding` |
| **Validates** | CSI driver can provision and bind a 10Mi PVC |
| **CSI APIs** | `CreateVolume`, `ControllerPublishVolume` |
| **Timeout** | 1 minute for PVC to bind |
| **Errors** | `pvc failed to bound` |

### 4. Storage Profiles Analysis

| Aspect | Details |
|--------|---------|
| **Function** | `checkStorageProfiles` |
| **Validates** | StorageProfile configuration and CSI capabilities |
| **Checks** | Empty ClaimPropertySets, Smart clone support, RWX support |
| **CSI APIs** | Validates `CLONE_VOLUME`, snapshot support |

### 5. VolumeSnapshotClass Validation

| Aspect | Details |
|--------|---------|
| **Function** | `checkVolumeSnapShotClasses` |
| **Validates** | VolumeSnapshotClass exists for snapshot-capable StorageProfiles |
| **CSI APIs** | `CREATE_DELETE_SNAPSHOT` capability |
| **Match Criteria** | VolumeSnapshotClass driver matches StorageProfile provisioner |

### 6. Golden Images Validation

| Aspect | Details |
|--------|---------|
| **Function** | `checkGoldenImages` |
| **Validates** | DataImportCrons are up-to-date, DataSources have valid sources |
| **Namespaces** | `openshift-virtualization-os-images` + all namespaces |
| **Conditions** | `UpToDate` on DataImportCron, `Ready` on DataSource |

### 7. VM Storage Class Validation

| Aspect | Details |
|--------|---------|
| **Function** | `checkVMIs` |
| **Validates** | Running VMs use optimal storage classes |
| **RBD Check** | Detects non-virtualization RBD class when optimized exists |
| **EFS Check** | Detects EFS class without `uid`/`gid` parameters |

### 8. VM Boot from Golden Image

| Aspect | Details |
|--------|---------|
| **Function** | `checkVMIBoot` |
| **Validates** | VM boots from cloned golden image, clone type is efficient |
| **CSI APIs** | `CreateVolume` (from snapshot or clone source) |
| **Clone Types** | `snapshot`, `csi-clone`, `host-assisted` (fallback) |
| **Boot Criteria** | Guest agent connects (`VirtualMachineInstanceAgentConnected`) |

### 9. VM Live Migration

| Aspect | Details |
|--------|---------|
| **Function** | `checkVMILiveMigration` |
| **Validates** | VM can live migrate with storage attached |
| **CSI APIs** | RWX capability (`MULTI_NODE_MULTI_WRITER`) |
| **Prerequisites** | Multi-node cluster, VMI is migratable |
| **Skip Conditions** | Single node, VMI not migratable |

### 10. VM Volume Hotplug

| Aspect | Details |
|--------|---------|
| **Function** | `checkVMIHotplugVolume` |
| **Validates** | Dynamic volume attach and detach to running VM |
| **CSI APIs** | `ControllerPublishVolume`, `NodeStageVolume`, `NodePublishVolume` (attach) |
| **CSI APIs** | `ControllerUnpublishVolume`, `NodeUnstageVolume`, `NodeUnpublishVolume` (detach) |
| **Volume State** | `Ready` after attach, removed after detach |

### 11. Concurrent VM Boot

| Aspect | Details |
|--------|---------|
| **Function** | `checkConcurrentVMIBoot` |
| **Validates** | Storage can handle concurrent clone and boot operations |
| **Default VMs** | 10 concurrent VMs |
| **CSI Stress** | Multiple `CreateVolume` operations in parallel |
| **Pass Criteria** | All VMs boot successfully |

---

## Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `spec.timeout` | Overall checkup timeout | 10m |
| `spec.param.storageClass` | Specific storage class to test | (default SC) |
| `spec.param.vmiTimeout` | Timeout for VMI operations | 3m |
| `spec.param.numOfVMs` | Number of concurrent VMs to boot | 10 |
| `spec.param.skipTeardown` | Skip cleanup (`always`, `onfailure`, `never`) | `never` |

---

## Unsupported Provisioners

The following provisioners are excluded from checks as they are known not to work with CDI:

| Provisioner | Reason |
|-------------|--------|
| `kubernetes.io/no-provisioner` | Local storage, no dynamic provisioning |
| `openshift-storage.ceph.rook.io/bucket` | Object storage (Rook/Ceph), not block/file |
| `openshift-storage.noobaa.io/obc` | Object storage (NooBaa), not block/file |

---

## References

- [Red Hat CSI Certification Documentation](http://docs.redhat.com/en/documentation/red_hat_software_certification/2025/html/red_hat_software_certification_workflow_guide/con_csi-certification_openshift-sw-cert-workflow-working-with-container-network-interface)
- [KubeVirt Storage Checkup GitHub](https://github.com/kiagnose/kubevirt-storage-checkup)
- [Running a storage checkup by using the web console](https://docs.openshift.com/container-platform/latest/virt/monitoring/virt-running-cluster-checkups.html)
- [CSI Addons Documentation](https://github.com/csi-addons/kubernetes-csi-addons/blob/main/cmd/csi-addons/README.md)
