# CSI Certification Tests Documentation

This document describes the CSI-related tests included in the KubeVirt Storage Checkup test suite, as required for [Red Hat Software Certification](http://docs.redhat.com/en/documentation/red_hat_software_certification/2025/html/red_hat_software_certification_workflow_guide/con_csi-certification_openshift-sw-cert-workflow-working-with-container-network-interface).

Related Jira: [OCPNAS-382](https://issues.redhat.com/browse/OCPNAS-382) - Locate and analyze existing CSI certification tests

## Technology Stack

The KubeVirt Storage Checkup is built using modern cloud-native technologies specifically designed for Kubernetes and OpenShift environments:

### Core Technologies
- **Language**: Go 1.19
- **Framework**: [Kiagnose](https://github.com/kiagnose/kiagnose) checkup engine for Kubernetes health validation
- **Testing Framework**: Ginkgo v2 & Gomega for unit/integration tests
- **Container Platform**: Designed for OpenShift with KubeVirt (CNV) virtualization

### Key Dependencies
- **Kubernetes APIs**: Core v1, Storage v1, Batch v1, RBAC v1
- **KubeVirt APIs**: VirtualMachine, VirtualMachineInstance operations
- **CSI Components**: External snapshotter client, VolumeSnapshot APIs  
- **CDI Integration**: Containerized Data Importer for VM disk management
- **OpenShift APIs**: Cluster version detection, OpenShift-specific resources

### Test Suite Architecture
The checkup runs as a **Kubernetes Job** with a comprehensive validation suite that executes **17 different test cases** to certify CSI driver compatibility with OpenShift Virtualization for **Red Hat Software Certification** requirements.

## Test Execution Architecture

The e2e test execution follows a **two-tier architecture** that separates host-side orchestration from in-cluster validation:

### E2E Test Flow

#### **1. Host-Side E2E Test (Ginkgo Framework)**
The e2e test runs on your **development machine** using Ginkgo/Gomega:

```go
// tests/tests_suite_test.go - Test suite setup
func TestTests(t *testing.T) {
    RegisterFailHandler(Fail)
    RunSpecs(t, "Tests Suite")
}
```

**Host-side responsibilities:**
- Sets up RBAC permissions (ServiceAccount, Role, RoleBinding)
- Creates ConfigMap with test parameters and configuration
- **Deploys a Kubernetes Job** that runs the actual checkup
- Monitors Job execution and completion status
- Retrieves and validates results from the ConfigMap

#### **2. In-Cluster Checkup Job**
The actual validation runs **inside the cluster** as a Kubernetes Job:

```yaml
# Created dynamically by the e2e test
apiVersion: batch/v1
kind: Job
spec:
  template:
    spec:
      serviceAccount: storage-checkup-sa
      containers:
      - name: storage-checkup
        image: quay.io/kiagnose/kubevirt-storage-checkup:main
        env:
        - name: CONFIGMAP_NAMESPACE
        - name: CONFIGMAP_NAME
```

**In-cluster Job responsibilities:**
- Executes all 17 test cases sequentially
- Interacts directly with Kubernetes and CSI APIs
- Writes detailed results back to the ConfigMap
- Handles cleanup based on `skipTeardown` configuration

### Makefile E2E Execution

```bash
# From Makefile target
e2e-test:
    $(CONTAINER_ENGINE) run --rm \
        -v $(PWD):$(PROJECT_WORKING_DIR):Z \
        -v $(HOME)/.kube:/root/.kube:Z \
        --workdir $(PROJECT_WORKING_DIR) \
        -e TEST_NAMESPACE=$(TEST_NAMESPACE) \
        -e TEST_IMAGE=$(TEST_IMAGE) \
        $(GO_IMAGE_NAME):$(GO_IMAGE_TAG) \
        go test -v ./tests/...
```

**Key execution features:**
- Runs in containerized Go 1.19 environment
- Mounts kubeconfig for cluster access
- Uses environment variables for configuration
- Supports parallel test execution

### Ginkgo Debugging Options

#### **Basic Debugging Flags**

| Flag | Purpose | Usage |
|------|---------|-------|
| `-ginkgo.v` | Verbose output | `go test ./tests/... -ginkgo.v` |
| `-ginkgo.progress` | Show test progress | `go test ./tests/... -ginkgo.progress` |
| `-ginkgo.focus="pattern"` | Run specific tests | `go test ./tests/... -ginkgo.focus="complete"` |
| `-ginkgo.skip="pattern"` | Skip specific tests | `go test ./tests/... -ginkgo.skip="teardown"` |
| `-ginkgo.dry-run` | Preview test plan | `go test ./tests/... -ginkgo.dry-run` |
| `-ginkgo.fail-fast` | Stop on first failure | `go test ./tests/... -ginkgo.fail-fast` |

#### **Advanced Debugging Session**

```bash
# Complete debugging setup
export TEST_NAMESPACE=debug-storage
export TEST_IMAGE=quay.io/kiagnose/kubevirt-storage-checkup:latest
export GINKGO_PRUNE_STACK=FALSE

# Run with comprehensive debugging
go test -v ./tests/... \
  -ginkgo.v -ginkgo.progress \
  -ginkgo.focus="should complete successfully" \
  --output-interceptor-mode=none \
  -timeout=20m

# Debug the in-cluster Job
kubectl logs -n debug-storage job/storage-checkup -f
kubectl get configmap storage-checkup-config -n debug-storage -o yaml

# Skip teardown for investigation
kubectl patch configmap storage-checkup-config -n debug-storage \
  --patch='{"data":{"spec.param.skipTeardown":"always"}}'
```

#### **Environment Variables for Debugging**

| Variable | Purpose | Value |
|----------|---------|-------|
| `GINKGO_PARALLEL_PROTOCOL` | Debug parallel execution | `HTTP` |
| `GINKGO_PRUNE_STACK` | Preserve stack traces | `FALSE` |
| `TEST_NAMESPACE` | Target namespace | Custom namespace |
| `TEST_IMAGE` | Checkup image | Development image |

This architecture provides **complete visibility** into both the host-side Ginkgo orchestration and the in-cluster Job execution, enabling effective debugging at both levels.

## What the CSI Tests Are Used For

### CSI Certification Requirements
The test suite validates CSI driver compliance with essential container storage interface operations:

| CSI Capability | Validation Method | Business Impact |
|----------------|------------------|-----------------|
| **Dynamic Volume Provisioning** (`CreateVolume`) | PVC creation and binding tests | Automated storage allocation |
| **Volume Attachment** (`ControllerPublishVolume`, `NodeStageVolume`) | VM boot and hotplug operations | Pod/VM storage connectivity |
| **Snapshot Operations** (`CreateSnapshot`, `DeleteSnapshot`) | Volume snapshot class validation | Data protection and backup |
| **Clone Operations** (CSI native cloning) | Smart clone detection and efficiency | Fast VM provisioning |
| **Multi-attach Support** (`MULTI_NODE_MULTI_WRITER`) | RWX validation and live migration | High availability workloads |
| **Hotplug Operations** (Dynamic attach/detach) | Runtime volume management | Elastic storage scaling |

### OpenShift Virtualization Validation
Beyond basic CSI compliance, the tests validate enterprise virtualization readiness:

- **VM Boot Performance** - Golden image cloning efficiency for rapid VM deployment
- **Storage Class Optimization** - RBD virtualization classes for optimal VM performance  
- **Live Migration** - RWX storage support for VM mobility across nodes
- **Concurrent Operations** - Storage scalability under multi-VM workload stress
- **Data Management** - DataImportCron and DataSource health for image lifecycle

### Infrastructure Compatibility Assessment
The comprehensive test suite validates that your storage infrastructure can:

1. **Handle VM Workloads Efficiently** - Tests storage performance under virtualization workloads
2. **Support OpenShift Virtualization Features** - Validates CNV-specific storage requirements
3. **Meet Performance Requirements** - Ensures production-ready VM performance characteristics
4. **Provide Data Protection** - Validates snapshot and clone capabilities for backup/restore
5. **Scale Under Load** - Tests concurrent VM operations and storage stress scenarios

### Enterprise Certification Benefits
- **Red Hat Support Eligibility** - Certified drivers receive full Red Hat support
- **Customer Confidence** - Proven compatibility with OpenShift Virtualization
- **Reduced Risk** - Comprehensive validation before production deployment
- **Performance Assurance** - Tests validate optimal storage configuration for VMs

---

## Prerequisites

Before running the KubeVirt Storage Checkup, ensure you have:

1. **OpenShift Cluster** with OpenShift Virtualization (CNV) installed
   - Minimum: 1 worker node (live migration test will be skipped)
   - Recommended: 2+ worker nodes (enables all tests including live migration)
2. **Cluster Admin Access** to create RBAC resources
3. **kubectl/oc CLI** configured to access the cluster
4. **CSI Driver** installed and configured with a StorageClass

---

## Cluster Requirements

| Requirement | Minimum | Recommended | Notes |
|-------------|---------|-------------|-------|
| **Cluster Type** | Single cluster | Single cluster | No multi-cluster setup needed |
| **Worker Nodes** | 1 | 2+ | Live migration test requires 2+ nodes |
| **Control Plane** | 1 | 3 | Standard HA configuration |
| **CNV Installed** | Yes | Yes | Required for VM-based tests (8-17) |
| **KVM Support** | Yes (for VM tests) | Yes | Worker nodes must have KVM virtualization |

### Test Requirements by Node Count

| Node Count | Tests Available | Tests Skipped |
|------------|-----------------|---------------|
| **Single node** | Tests 1-13, 15-17 (15 tests) | Test 14: VM Live Migration |
| **Multi-node (2+)** | All 17 tests | None |

> **Note:** The Live Migration test (Test 14) is automatically skipped on single-node clusters with the message: `"Skipping, single node cluster"`. This is not a failure - it's expected behavior.

### AWS Instance Type Requirements

For running VM-based tests (8-17) on AWS, worker nodes **must use bare metal instance types** that support KVM virtualization:

| Instance Type | vCPUs | Memory | Supports KVM | Cost/hr | Notes |
|---------------|-------|--------|--------------|---------|-------|
| `m5.2xlarge` | 8 | 32 GiB | ❌ No | ~$0.38 | Default - storage tests only |
| **`m5zn.metal`** | 48 | 192 GiB | ✅ Yes | ~$3.96 | **Recommended** - best cost/performance |
| `c5.metal` | 96 | 192 GiB | ✅ Yes | ~$4.08 | Compute optimized |
| `m5.metal` | 96 | 384 GiB | ✅ Yes | ~$4.60 | Large memory workloads |
| `m5n.metal` | 96 | 384 GiB | ✅ Yes | ~$4.77 | Enhanced networking |
| `r5.metal` | 96 | 768 GiB | ✅ Yes | ~$6.05 | Memory optimized |

> **Important:** Regular EC2 instance types (e.g., `m5.2xlarge`) do not expose the `/dev/kvm` device required for running VMs. Only `.metal` instance types provide hardware virtualization support.

### Test Categories by Infrastructure

| Tests | Description | Requires CNV | Requires KVM |
|-------|-------------|--------------|--------------|
| 1-7 | Storage validation (PVC, clone, snapshot) | ❌ No | ❌ No |
| 8-17 | VM operations (boot, migrate, hotplug) | ✅ Yes | ✅ Yes |

If your cluster workers don't have KVM support, only tests 1-7 will pass. Tests 8-17 will fail with:
```
0/N nodes are available: N Insufficient devices.kubevirt.io/kvm
```

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

The following table comprehensively maps test cases to the underlying CSI specification APIs being exercised, providing detailed coverage analysis:

### Primary CSI API Coverage

| Test Case | CSI API Method | CSI Capability | Validation Purpose |
|-----------|----------------|----------------|-------------------|
| **PVC Creation & Binding** | `CreateVolume` | `CREATE_DELETE_VOLUME` | Tests dynamic volume provisioning from storage backend |
| **PVC Creation & Binding** | `ControllerPublishVolume` | `PUBLISH_UNPUBLISH_VOLUME` | Tests volume attachment to Kubernetes node |
| **Storage Profiles - Smart Clone** | `CreateVolume` (clone source) | `CLONE_VOLUME` | Tests CSI native volume cloning capability |
| **VolumeSnapshotClass** | `CreateSnapshot` | `CREATE_DELETE_SNAPSHOT` | Tests volume snapshot creation capability |
| **VolumeSnapshotClass** | `DeleteSnapshot` | `CREATE_DELETE_SNAPSHOT` | Tests volume snapshot cleanup capability |
| **VM Boot from Golden Image** | `CreateVolume` (from snapshot/clone) | `CLONE_VOLUME` | Tests volume creation from existing snapshot or clone |
| **Volume Clone Type** | `CreateVolume` (clone) | `CLONE_VOLUME` | Tests CSI-native vs host-assisted cloning efficiency |
| **VM Live Migration** | `NodePublishVolume`/`NodeUnpublishVolume` | `MULTI_NODE_MULTI_WRITER` | Tests RWX volume multi-attach capability across nodes |
| **Volume Hotplug - Attach** | `ControllerPublishVolume` | `PUBLISH_UNPUBLISH_VOLUME` | Tests dynamic volume attachment to running workloads |
| **Volume Hotplug - Attach** | `NodeStageVolume` | `STAGE_UNSTAGE_VOLUME` | Tests volume staging on target node |
| **Volume Hotplug - Attach** | `NodePublishVolume` | `STAGE_UNSTAGE_VOLUME` | Tests volume mount into pod/VM filesystem |
| **Volume Hotplug - Detach** | `ControllerUnpublishVolume` | `PUBLISH_UNPUBLISH_VOLUME` | Tests dynamic volume detachment from workloads |
| **Volume Hotplug - Detach** | `NodeUnstageVolume` | `STAGE_UNSTAGE_VOLUME` | Tests volume unmounting from pod/VM filesystem |
| **Volume Hotplug - Detach** | `NodeUnpublishVolume` | `STAGE_UNSTAGE_VOLUME` | Tests volume unstaging from target node |

### CSI Controller Service Methods Tested

| CSI Controller Method | Test Coverage | Validation Details |
|----------------------|---------------|-------------------|
| `CreateVolume` | ✅ Comprehensive | PVC binding, clone creation, snapshot-based volumes |
| `DeleteVolume` | ✅ Implicit | Cleanup during test teardown phases |
| `ControllerPublishVolume` | ✅ Explicit | VM boot, volume hotplug attach operations |
| `ControllerUnpublishVolume` | ✅ Explicit | Volume hotplug detach operations |
| `ValidateVolumeCapabilities` | ✅ Implicit | Access mode validation (RWO, RWX) |
| `ListVolumes` | ❌ Not tested | Not required for certification |
| `GetCapacity` | ❌ Not tested | Not required for certification |
| `CreateSnapshot` | ✅ Explicit | VolumeSnapshotClass validation |
| `DeleteSnapshot` | ✅ Explicit | Snapshot cleanup operations |

### CSI Node Service Methods Tested

| CSI Node Method | Test Coverage | Validation Details |
|----------------|---------------|-------------------|
| `NodeStageVolume` | ✅ Explicit | Volume hotplug attach, VM boot operations |
| `NodeUnstageVolume` | ✅ Explicit | Volume hotplug detach operations |
| `NodePublishVolume` | ✅ Explicit | Mount volume into VM/pod filesystem |
| `NodeUnpublishVolume` | ✅ Explicit | Unmount volume from VM/pod filesystem |
| `NodeGetCapabilities` | ✅ Implicit | Capability discovery during operations |
| `NodeGetInfo` | ✅ Implicit | Node topology information retrieval |

### CSI Capabilities Validated

The test suite provides comprehensive validation of CSI driver capabilities required for enterprise virtualization workloads:

| CSI Capability | Validation Method | Pass Criteria |
|----------------|------------------|---------------|
| `CREATE_DELETE_VOLUME` | PVC creation, VM boot, cleanup operations | Volumes provision and delete successfully |
| `CREATE_DELETE_SNAPSHOT` | VolumeSnapshotClass validation, clone from snapshot | Snapshots create/delete without errors |
| `CLONE_VOLUME` | Smart clone detection, efficient cloning tests | CSI-native cloning preferred over host-assisted |
| `PUBLISH_UNPUBLISH_VOLUME` | VM boot, hotplug operations, live migration | Volumes attach/detach cleanly across lifecycle |
| `STAGE_UNSTAGE_VOLUME` | Hotplug attach/detach, mount/unmount operations | Volume staging/unstaging completes successfully |
| `MULTI_NODE_MULTI_WRITER` | RWX validation, live migration tests | RWX volumes support concurrent multi-node access |

### Advanced CSI Feature Coverage

| Feature Category | Specific Tests | Enterprise Value |
|------------------|----------------|------------------|
| **Cloning Efficiency** | CSI-native vs snapshot vs host-assisted cloning | Rapid VM deployment from golden images |
| **Multi-Attach Support** | RWX access modes, live migration compatibility | High availability VM workloads |
| **Dynamic Operations** | Volume hotplug attach/detach while VM running | Elastic storage without downtime |
| **Concurrent Access** | Multiple VM boot, stress testing scenarios | Storage scalability validation |
| **Data Protection** | Snapshot creation/deletion, backup workflows | Enterprise data protection requirements |

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
