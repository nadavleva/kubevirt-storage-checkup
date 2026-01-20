# CSI Addons Replication API

This document describes the CSI Addons Volume Replication API, its operations, and the workflow for implementing disaster recovery with replicated storage.

Reference: [kubernetes-csi-addons](https://github.com/csi-addons/kubernetes-csi-addons)

---

## Overview

The CSI Addons project extends the Container Storage Interface (CSI) specification with additional operations not covered by the core CSI spec. Volume Replication is one of these extensions, enabling disaster recovery (DR) capabilities for persistent volumes.

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Primary Volume** | The active volume where applications read/write data |
| **Secondary Volume** | A replica volume that mirrors the primary, typically in a different cluster/site |
| **Failover** | Promoting a secondary volume to primary when the original primary fails |
| **Failback** | Returning to the original primary after recovery |
| **Resync** | Synchronizing data between primary and secondary after a failover event |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Primary Cluster                                 │
│  ┌──────────────┐    ┌──────────────────┐    ┌──────────────────────────┐   │
│  │ Application  │───▶│ PersistentVolume │───▶│ CSI Driver + Replication │   │
│  │   (Pod/VM)   │    │      (PVC)       │    │        Sidecar           │   │
│  └──────────────┘    └──────────────────┘    └────────────┬─────────────┘   │
│                                                           │                  │
└───────────────────────────────────────────────────────────┼──────────────────┘
                                                            │
                                              Replication   │
                                                 Link       │
                                                            ▼
┌───────────────────────────────────────────────────────────┼──────────────────┐
│                                                           │                  │
│  ┌──────────────┐    ┌──────────────────┐    ┌────────────▼─────────────┐   │
│  │ Application  │    │ PersistentVolume │◀───│ CSI Driver + Replication │   │
│  │  (Standby)   │    │   (Secondary)    │    │        Sidecar           │   │
│  └──────────────┘    └──────────────────┘    └──────────────────────────┘   │
│                              Secondary Cluster                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Replication API Operations

The CSI Addons sidecar exposes the following replication operations via a Unix socket:

### Core Operations

| Operation | Description | When Used |
|-----------|-------------|-----------|
| `EnableVolumeReplication` | Enables replication for a volume | Initial setup, adding volumes to DR |
| `DisableVolumeReplication` | Disables replication for a volume | Removing volumes from DR |
| `PromoteVolume` | Promotes a secondary volume to primary | Failover scenarios |
| `DemoteVolume` | Demotes a primary volume to secondary | Planned migration, failback |
| `ResyncVolume` | Resynchronizes volume data | After failover/failback |
| `GetVolumeReplicationInfo` | Gets replication status and metadata | Monitoring, health checks |

### CLI Usage

The `csi-addons` CLI tool can invoke these operations directly:

```bash
# Enable replication on a volume
kubectl exec -c csi-addons <pod> -- csi-addons \
  -operation EnableVolumeReplication \
  -persistentvolume <pv-name> \
  -parameters mirroringMode=snapshot,schedulingInterval=1m

# Get replication status
kubectl exec -c csi-addons <pod> -- csi-addons \
  -operation GetVolumeReplicationInfo \
  -volumeids <volume-id>

# Promote secondary to primary
kubectl exec -c csi-addons <pod> -- csi-addons \
  -operation PromoteVolume \
  -volumeids <volume-id>

# Demote primary to secondary
kubectl exec -c csi-addons <pod> -- csi-addons \
  -operation DemoteVolume \
  -volumeids <volume-id>

# Resync after failover
kubectl exec -c csi-addons <pod> -- csi-addons \
  -operation ResyncVolume \
  -volumeids <volume-id>

# Disable replication
kubectl exec -c csi-addons <pod> -- csi-addons \
  -operation DisableVolumeReplication \
  -volumeids <volume-id>
```

---

## Kubernetes Custom Resources

### VolumeReplicationClass

Defines the replication policy and parameters for a CSI driver:

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplicationClass
metadata:
  name: rbd-volumereplicationclass
spec:
  # Must match the CSI driver's provisioner
  provisioner: openshift-storage.rbd.csi.ceph.com
  parameters:
    # Replication mode: "snapshot" or "async"
    mirroringMode: snapshot
    # How often to sync (for async mode)
    schedulingInterval: 1m
    # Secret for replication credentials
    replication.storage.openshift.io/replication-secret-name: rook-csi-rbd-provisioner
    replication.storage.openshift.io/replication-secret-namespace: openshift-storage
```

### VolumeReplication

Manages replication state for a specific PVC:

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplication
metadata:
  name: my-pvc-replication
  namespace: my-app
spec:
  # Reference to the VolumeReplicationClass
  volumeReplicationClass: rbd-volumereplicationclass
  
  # Desired replication state
  # - "primary": Volume is the active primary
  # - "secondary": Volume is a passive replica
  # - "resync": Trigger resynchronization
  replicationState: primary
  
  # The PVC to replicate
  dataSource:
    kind: PersistentVolumeClaim
    name: my-pvc
```

### VolumeReplication Status

The controller updates the status to reflect the actual state:

```yaml
status:
  # Current observed state
  state: Primary  # or Secondary, Resyncing, Unknown
  
  # Human-readable message
  message: "Volume is primary and replication is healthy"
  
  # Conditions for detailed status
  conditions:
    - type: Completed
      status: "True"
      reason: Promoted
      message: "Volume promoted to primary"
      lastTransitionTime: "2024-01-15T10:30:00Z"
    
    - type: Degraded
      status: "False"
      reason: Healthy
      message: "Replication is synchronized"
    
    - type: Resyncing
      status: "False"
      reason: NotResyncing
      message: "No resync in progress"
  
  # Replication metrics
  lastSyncTime: "2024-01-15T10:29:00Z"
  lastSyncDuration: "2s"
  lastSyncBytes: 1048576
```

---

## Replication Workflows

### Workflow 1: Initial Setup

Enable replication on a new or existing PVC:

```
┌─────────────────┐
│  1. Create PVC  │
│  (if new)       │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────┐
│  2. Create VolumeReplication │
│     CR with state: primary   │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  3. Controller calls         │
│  EnableVolumeReplication     │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  4. CSI driver enables       │
│  mirroring to secondary site │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  5. Status updated to        │
│  state: Primary, Completed   │
└─────────────────────────────┘
```

### Workflow 2: Planned Failover (Graceful Migration)

Migrate workload to secondary site with zero data loss:

```
Primary Cluster                         Secondary Cluster
─────────────────                       ──────────────────

┌─────────────────┐
│ 1. Stop/Fence   │
│    Application  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 2. Wait for     │
│    final sync   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 3. Demote       │
│    to secondary │ ─────────────────────────▶ ┌─────────────────┐
└─────────────────┘                            │ 4. Promote      │
                                               │    to primary   │
                                               └────────┬────────┘
                                                        │
                                                        ▼
                                               ┌─────────────────┐
                                               │ 5. Start        │
                                               │    Application  │
                                               └─────────────────┘
```

### Workflow 3: Disaster Recovery (Unplanned Failover)

Recover from primary site failure:

```
Primary Cluster (FAILED)                Secondary Cluster
────────────────────────               ──────────────────

     ╳ Site Down ╳                     ┌─────────────────┐
                                       │ 1. Detect       │
                                       │    failure      │
                                       └────────┬────────┘
                                                │
                                                ▼
                                       ┌─────────────────┐
                                       │ 2. Force        │
                                       │    Promote      │
                                       └────────┬────────┘
                                                │
                                                ▼
                                       ┌─────────────────┐
                                       │ 3. Start        │
                                       │    Application  │
                                       └────────┬────────┘
                                                │
                                                ▼
                                       ┌─────────────────┐
                                       │ 4. Application  │
                                       │    Running      │
                                       └─────────────────┘
```

### Workflow 4: Failback After Recovery

Return to original primary after site recovery:

```
Original Primary (Recovered)            Current Primary
────────────────────────────           ────────────────

┌─────────────────┐
│ 1. Site         │
│    Recovered    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐                    ┌─────────────────┐
│ 2. Resync       │◀───────────────────│ 3. Trigger      │
│    Volume       │                    │    Resync       │
└────────┬────────┘                    └─────────────────┘
         │
         ▼
┌─────────────────┐                    ┌─────────────────┐
│ 4. Wait for     │                    │ 5. Stop         │
│    sync complete│                    │    Application  │
└────────┬────────┘                    └────────┬────────┘
         │                                      │
         ▼                                      ▼
┌─────────────────┐                    ┌─────────────────┐
│ 6. Promote      │◀───────────────────│ 7. Demote       │
│    to primary   │                    │    to secondary │
└────────┬────────┘                    └─────────────────┘
         │
         ▼
┌─────────────────┐
│ 8. Start        │
│    Application  │
└─────────────────┘
```

---

## Replication Modes

### Synchronous Replication

- Data is written to both primary and secondary before acknowledging
- **RPO**: Zero (no data loss)
- **Performance**: Higher latency
- **Use case**: Critical data requiring zero data loss

### Asynchronous Replication (Snapshot-based)

- Data is periodically synced via snapshots
- **RPO**: Depends on sync interval (e.g., 1 minute)
- **Performance**: Lower latency, less bandwidth
- **Use case**: Geographically distributed sites

```yaml
# Async replication with 5-minute interval
parameters:
  mirroringMode: snapshot
  schedulingInterval: 5m
```

---

## CSI Driver Requirements

For a CSI driver to support replication, it must:

1. **Implement CSI Addons Replication Service**
   - `EnableVolumeReplication`
   - `DisableVolumeReplication`
   - `PromoteVolume`
   - `DemoteVolume`
   - `ResyncVolume`
   - `GetVolumeReplicationInfo`

2. **Deploy CSI Addons Sidecar**
   ```yaml
   containers:
     - name: csi-addons
       image: quay.io/csiaddons/k8s-sidecar:latest
       args:
         - "--node-id=$(NODE_ID)"
         - "--endpoint=$(CSI_ENDPOINT)"
         - "--controller-port=9070"
   ```

3. **Support Underlying Storage Replication**
   - Ceph RBD: RBD Mirroring
   - Dell PowerStore: Replication Sessions
   - NetApp ONTAP: SnapMirror
   - Pure Storage: ActiveCluster

---

## Supported CSI Drivers

| CSI Driver | Replication Support | Notes |
|------------|---------------------|-------|
| Ceph RBD (`rbd.csi.ceph.com`) | ✅ Yes | RBD mirroring (snapshot/journal mode) |
| Ceph CephFS | ❌ No | Not supported |
| Dell PowerStore | ✅ Yes | Replication sessions |
| Dell PowerScale | ✅ Yes | SyncIQ |
| NetApp Trident | ✅ Yes | SnapMirror |
| Pure Storage | ✅ Yes | ActiveCluster |
| IBM Spectrum Scale | ⚠️ Partial | AFM-based replication |

---

## Monitoring and Observability

### Prometheus Metrics

The CSI Addons controller exposes metrics:

```promql
# Replication state
csi_addons_volumereplication_state{name="my-pvc-replication", state="primary"}

# Last sync time
csi_addons_volumereplication_last_sync_time{name="my-pvc-replication"}

# Sync duration
csi_addons_volumereplication_last_sync_duration_seconds{name="my-pvc-replication"}
```

### Alerts

Example Prometheus alerts for replication health:

```yaml
groups:
  - name: csi-replication
    rules:
      - alert: VolumeReplicationDegraded
        expr: csi_addons_volumereplication_state{state="degraded"} == 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Volume replication is degraded"
          
      - alert: VolumeReplicationSyncStale
        expr: time() - csi_addons_volumereplication_last_sync_time > 600
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Volume replication sync is stale (>10 minutes)"
```

---

## Error Handling

### Common Errors

| Error | Cause | Resolution |
|-------|-------|------------|
| `FailedToEnableReplication` | CSI driver doesn't support replication | Use compatible driver/storage |
| `ReplicationPeerNotFound` | Secondary cluster not configured | Configure peer cluster |
| `VolumeDegraded` | Network/storage issue | Check connectivity and storage health |
| `SyncFailed` | Data sync interrupted | Trigger resync operation |
| `PromoteFailed` | Cannot promote (still syncing) | Wait for sync or force promote |

### Recovery Procedures

**Stuck in Resyncing state:**
```bash
# Check the VolumeReplication status
kubectl get volumereplication my-pvc-replication -o yaml

# If stuck, delete and recreate
kubectl delete volumereplication my-pvc-replication
kubectl apply -f volumereplication.yaml
```

**Force promote (data loss risk):**
```bash
kubectl exec -c csi-addons <pod> -- csi-addons \
  -operation PromoteVolume \
  -volumeids <volume-id> \
  -parameters force=true
```

---

## References

- [CSI Addons Project](https://github.com/csi-addons/kubernetes-csi-addons)
- [CSI Addons CLI Documentation](https://github.com/csi-addons/kubernetes-csi-addons/blob/main/cmd/csi-addons/README.md)
- [Rook Ceph RBD Mirroring](https://rook.io/docs/rook/latest/Storage-Configuration/Ceph-CSI/ceph-csi-dr/)
- [OpenShift Data Foundation DR](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_foundation/)
- [CSI Specification](https://github.com/container-storage-interface/spec)

