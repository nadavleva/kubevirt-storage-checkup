# CSI Addons Replication Tests - Proposed

This document describes CSI Addons Replication tests that should be added to the KubeVirt Storage Checkup test suite to validate volume replication capabilities.

Reference: [CSI Addons README](https://github.com/csi-addons/kubernetes-csi-addons/blob/main/cmd/csi-addons/README.md)

---

## Overview

The [kubernetes-csi-addons](https://github.com/csi-addons/kubernetes-csi-addons) project provides additional CSI operations beyond the core CSI specification. For storage certification with OpenShift Virtualization, testing replication capabilities is essential for disaster recovery scenarios.

### CSI Addons Replication Operations

The CSI Addons sidecar supports the following replication operations:

| Operation | Description |
|-----------|-------------|
| `EnableVolumeReplication` | Enable replication for a volume |
| `DisableVolumeReplication` | Disable replication for a volume |
| `PromoteVolume` | Promote a secondary volume to primary |
| `DemoteVolume` | Demote a primary volume to secondary |
| `ResyncVolume` | Resynchronize a volume after failover |
| `GetVolumeReplicationInfo` | Get replication status information |

---

## Cluster Requirements

### Single-Cluster vs Multi-Cluster

| Scenario | Cluster Setup | Description |
|----------|---------------|-------------|
| **API Validation** | Single cluster | Tests replication APIs work correctly |
| **Full DR Testing** | Multi-cluster | Tests actual disaster recovery failover |

### Detailed Requirements

| Requirement | Single-Cluster Mode | Multi-Cluster Mode |
|-------------|---------------------|-------------------|
| **Clusters Needed** | 1 | 2 (primary + secondary) |
| **Worker Nodes** | 1+ | 1+ per cluster |
| **Storage Backend** | Replication-capable CSI driver | Same driver on both clusters |
| **Network** | Standard | Cross-cluster connectivity |
| **CNV Required** | Only for Tests 7-8 | Only for Tests 7-8 |

### Test Availability by Cluster Setup

| Test | Single Cluster | Multi-Cluster | CNV Required |
|------|----------------|---------------|--------------|
| 1. Enable Volume Replication | ✅ Yes | ✅ Yes | ❌ No |
| 2. Get Replication Info | ✅ Yes | ✅ Yes | ❌ No |
| 3. Demote Primary Volume | ✅ Yes | ✅ Yes | ❌ No |
| 4. Promote Secondary Volume | ✅ Yes | ✅ Yes | ❌ No |
| 5. Resync Volume | ⚠️ Limited | ✅ Yes | ❌ No |
| 6. Disable Volume Replication | ✅ Yes | ✅ Yes | ❌ No |
| 7. VM with Replicated Storage | ✅ Yes | ✅ Yes | ✅ Yes |
| 8. Failover with Running VM | ❌ No | ✅ Yes | ✅ Yes |

> **Note:** 
> - **Single-cluster mode** validates that the CSI driver correctly implements the replication API operations. The storage backend may create local replicas or operate in a degraded mode.
> - **Multi-cluster mode** is required for testing actual disaster recovery scenarios where data is replicated across geographically separated sites.
> - **Resync** in single-cluster mode may only verify the API call succeeds, not actual data synchronization.

---

## Proposed Test Cases

### Replication Test Suite

| # | Test Case | What is Validated | CSI Addons Operation | Pass Criteria |
|---|-----------|-------------------|---------------------|---------------|
| 1 | Enable Volume Replication | Replication can be enabled on a PVC | `EnableVolumeReplication` | Replication enabled without error |
| 2 | Get Replication Info | Replication status is retrievable | `GetVolumeReplicationInfo` | Status returned with valid state |
| 3 | Demote Primary Volume | Primary volume can be demoted to secondary | `DemoteVolume` | Volume state changes to secondary |
| 4 | Promote Secondary Volume | Secondary volume can be promoted to primary | `PromoteVolume` | Volume state changes to primary |
| 5 | Resync Volume | Volume can be resynchronized | `ResyncVolume` | Resync completes successfully |
| 6 | Disable Volume Replication | Replication can be disabled | `DisableVolumeReplication` | Replication disabled without error |
| 7 | VM with Replicated Storage | VM boots from replicated volume | N/A (integration) | VM boots and operates normally |
| 8 | Failover with Running VM | VM can failover to replicated volume | `PromoteVolume` | VM recovers on promoted volume |

---

## Detailed Test Specifications

### Test 1: Enable Volume Replication

```go
func (c *Checkup) checkEnableVolumeReplication(ctx context.Context, errStr *string) error {
    // Prerequisites:
    // - VolumeReplicationClass exists with matching provisioner
    // - CSI driver supports replication
    
    // Steps:
    // 1. Create a PVC with replication-capable storage class
    // 2. Create VolumeReplication CR targeting the PVC
    // 3. Wait for VolumeReplication to reach "primary" state
    // 4. Verify replication is enabled via CSI Addons
    
    // Expected Result:
    // - VolumeReplication CR status shows "Completed"
    // - Volume is in "primary" role
}
```

**Kubernetes Resources:**

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplication
metadata:
  name: test-volume-replication
spec:
  volumeReplicationClass: <replication-class>
  replicationState: primary
  dataSource:
    kind: PersistentVolumeClaim
    name: test-pvc
```

### Test 2: Get Volume Replication Info

```go
func (c *Checkup) checkGetVolumeReplicationInfo(ctx context.Context, errStr *string) error {
    // Prerequisites:
    // - Volume replication is enabled
    
    // Steps:
    // 1. Call GetVolumeReplicationInfo via CSI Addons
    // 2. Parse replication status
    // 3. Verify expected fields are present
    
    // Expected Result:
    // - Replication state (primary/secondary)
    // - Last sync time
    // - Sync status
}
```

### Test 3: Demote Primary Volume

```go
func (c *Checkup) checkDemoteVolume(ctx context.Context, errStr *string) error {
    // Prerequisites:
    // - Volume is in "primary" state
    
    // Steps:
    // 1. Update VolumeReplication CR to "secondary" state
    // 2. Wait for state transition
    // 3. Verify volume is demoted
    
    // Expected Result:
    // - Volume role changes to "secondary"
    // - I/O is blocked on the volume
}
```

### Test 4: Promote Secondary Volume

```go
func (c *Checkup) checkPromoteVolume(ctx context.Context, errStr *string) error {
    // Prerequisites:
    // - Volume is in "secondary" state
    
    // Steps:
    // 1. Update VolumeReplication CR to "primary" state
    // 2. Wait for state transition
    // 3. Verify volume is promoted
    
    // Expected Result:
    // - Volume role changes to "primary"
    // - I/O is allowed on the volume
}
```

### Test 5: Resync Volume

```go
func (c *Checkup) checkResyncVolume(ctx context.Context, errStr *string) error {
    // Prerequisites:
    // - Volume replication enabled
    // - Data may be out of sync
    
    // Steps:
    // 1. Trigger resync via VolumeReplication CR
    // 2. Wait for resync completion
    // 3. Verify sync status
    
    // Expected Result:
    // - Resync completes without error
    // - Last sync time updated
}
```

### Test 6: Disable Volume Replication

```go
func (c *Checkup) checkDisableVolumeReplication(ctx context.Context, errStr *string) error {
    // Prerequisites:
    // - Volume replication is enabled
    
    // Steps:
    // 1. Delete VolumeReplication CR
    // 2. Wait for cleanup
    // 3. Verify replication is disabled
    
    // Expected Result:
    // - VolumeReplication CR deleted
    // - Volume operates as standalone
}
```

### Test 7: VM with Replicated Storage

```go
func (c *Checkup) checkVMWithReplicatedStorage(ctx context.Context, errStr *string) error {
    // Prerequisites:
    // - Replication-capable storage class
    // - Golden image available
    
    // Steps:
    // 1. Create VM with replicated DataVolume
    // 2. Enable replication on the volume
    // 3. Boot VM and verify operation
    // 4. Write test data to VM disk
    // 5. Verify data persists
    
    // Expected Result:
    // - VM boots on replicated storage
    // - I/O operations succeed
    // - Replication status shows synced
}
```

### Test 8: Failover with Running VM

```go
func (c *Checkup) checkVMFailover(ctx context.Context, errStr *string) error {
    // Prerequisites:
    // - Multi-cluster or simulated failover environment
    // - VM running on primary volume
    
    // Steps:
    // 1. Stop VM on primary
    // 2. Demote primary volume
    // 3. Promote secondary volume
    // 4. Start VM on promoted volume
    // 5. Verify data integrity
    
    // Expected Result:
    // - Failover completes
    // - VM boots on promoted volume
    // - Data is consistent
}
```

---

## CSI Addons Client Interface

To implement these tests, add the following interface to the checkup client:

```go
type csiAddonsClient interface {
    // Volume Replication operations
    EnableVolumeReplication(ctx context.Context, volumeID string, params map[string]string) error
    DisableVolumeReplication(ctx context.Context, volumeID string) error
    PromoteVolume(ctx context.Context, volumeID string, force bool) error
    DemoteVolume(ctx context.Context, volumeID string) error
    ResyncVolume(ctx context.Context, volumeID string) error
    GetVolumeReplicationInfo(ctx context.Context, volumeID string) (*VolumeReplicationInfo, error)
}

type VolumeReplicationInfo struct {
    State           string    // "primary", "secondary", "unknown"
    LastSyncTime    time.Time
    LastSyncBytes   int64
    Message         string
}
```

---

## Kubernetes CRDs Required

### VolumeReplicationClass

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplicationClass
metadata:
  name: rbd-volumereplicationclass
spec:
  provisioner: openshift-storage.rbd.csi.ceph.com
  parameters:
    mirroringMode: snapshot
    schedulingInterval: 1m
    replication.storage.openshift.io/replication-secret-name: rook-csi-rbd-provisioner
    replication.storage.openshift.io/replication-secret-namespace: openshift-storage
```

### VolumeReplication

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplication
metadata:
  name: pvc-volume-replication
  namespace: <namespace>
spec:
  volumeReplicationClass: rbd-volumereplicationclass
  replicationState: primary  # or "secondary", "resync"
  dataSource:
    kind: PersistentVolumeClaim
    name: <pvc-name>
```

---

## Configuration Options (Proposed)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `spec.param.enableReplicationTests` | Enable replication test suite | `false` |
| `spec.param.volumeReplicationClass` | VolumeReplicationClass to use | (auto-detect) |
| `spec.param.replicationTimeout` | Timeout for replication operations | 5m |
| `spec.param.skipFailoverTest` | Skip failover test (requires multi-cluster) | `true` |
| `spec.param.secondaryClusterKubeconfig` | Kubeconfig for secondary cluster (multi-cluster mode) | (none) |

---

## Results Keys (Proposed)

| Key | Description |
|-----|-------------|
| `status.result.volumeReplicationEnabled` | Volume replication enable status |
| `status.result.volumeReplicationInfo` | Replication info retrieval status |
| `status.result.volumeDemotion` | Volume demotion status |
| `status.result.volumePromotion` | Volume promotion status |
| `status.result.volumeResync` | Volume resync status |
| `status.result.volumeReplicationDisabled` | Volume replication disable status |
| `status.result.vmWithReplicatedStorage` | VM on replicated storage status |
| `status.result.vmFailover` | VM failover status |

---

## Implementation Priority

| Priority | Test | Rationale |
|----------|------|-----------|
| P1 | Enable/Disable Replication | Core functionality |
| P1 | Get Replication Info | Essential for status verification |
| P2 | Promote/Demote Volume | Failover operations |
| P2 | Resync Volume | Recovery operations |
| P3 | VM with Replicated Storage | Integration test |
| P3 | VM Failover | Complex DR scenario |

---

## Other CSI Addons Operations (Future)

The following CSI Addons operations could be tested in future iterations:

| Operation | Description | Priority |
|-----------|-------------|----------|
| `ControllerReclaimSpace` | Reclaim unused space from volume | P2 |
| `NodeReclaimSpace` | Node-level space reclamation | P2 |
| `NetworkFence` | Block network access to volume | P3 |
| `NetworkUnFence` | Restore network access to volume | P3 |
| `CreateVolumeGroup` | Create a volume group | P3 |
| `ModifyVolumeGroupMembership` | Modify volume group membership | P3 |
| `DeleteVolumeGroup` | Delete a volume group | P3 |
| `ControllerGetVolumeGroup` | Get volume group information | P3 |

---

## References

- [CSI Addons - kubernetes-csi-addons](https://github.com/csi-addons/kubernetes-csi-addons)
- [CSI Addons CLI Tool](https://github.com/csi-addons/kubernetes-csi-addons/blob/main/cmd/csi-addons/README.md)
- [OpenShift Data Foundation - Volume Replication](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_foundation/)
- [Rook Ceph Mirroring](https://rook.io/docs/rook/latest/Storage-Configuration/Ceph-CSI/ceph-csi-dr/)

