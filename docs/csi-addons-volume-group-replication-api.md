# CSI Addons Volume Group Replication API

This document describes the CSI Addons Volume Group Replication API, which extends the single volume replication capabilities to support replication of multiple volumes as a group, ensuring consistency across the entire group during replication operations.

Reference: [kubernetes-csi-addons Volume Group Replication](https://github.com/csi-addons/kubernetes-csi-addons/blob/main/api/replication.storage/v1alpha1/volumegroupreplication_types.go)

---

## Overview

Volume Group Replication builds upon the CSI Addons Volume Replication API to provide group-level replication capabilities. This ensures that multiple related volumes can be replicated together with consistency guarantees, which is essential for applications that span multiple persistent volumes (such as databases with separate data, log, and backup volumes).

### Key Benefits

| Benefit | Description |
|---------|-------------|
| **Consistency** | All volumes in a group are replicated atomically |
| **Simplified Management** | Single resource to manage multiple volume replications |
| **Application-Level DR** | Support for complex applications with multiple storage requirements |
| **Crash Consistency** | Group snapshots ensure consistent point-in-time replicas |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                               Primary Cluster                                        │
│                                                                                       │
│  ┌─────────────────┐    ┌─────────────────────┐    ┌─────────────────────────────┐   │
│  │   Application   │───▶│  PVC Group (Data)   │───▶│ VolumeGroupReplication      │   │
│  │     (DB)        │    │  - pvc-data         │    │         (VGR)               │   │
│  │                 │    │  - pvc-logs         │    │                             │   │
│  │                 │    │  - pvc-backup       │    │   ┌─────────────────────┐   │   │
│  └─────────────────┘    └─────────────────────┘    │   │ VolumeReplication   │   │   │
│                                                     │   │       (VR)          │   │   │
│                          ┌─────────────────────┐    │   └─────────────────────┘   │   │
│                          │VolumeGroupReplication│    │                             │   │
│                          │      Content        │◀───┤   ┌─────────────────────┐   │   │
│                          │     (VGRContent)    │    │   │ CSI Driver +        │   │   │
│                          └─────────────────────┘    │   │ Replication Sidecar │   │   │
│                                                     └───┴─────────────┬───────┘   │   │
│                                                                       │           │   │
└───────────────────────────────────────────────────────────────────────┼───────────────┘
                                                                        │
                                                        Group Replication │
                                                                         │
                                                                         ▼
┌───────────────────────────────────────────────────────────────────────┼───────────────┐
│                                                                       │           │   │
│  ┌─────────────────┐    ┌─────────────────────┐    ┌─────────────────┴─────────┐   │   │
│  │   Application   │    │  PVC Group (Data)   │◀───│ VolumeGroupReplication    │   │   │
│  │   (Standby)     │    │  - pvc-data-sec     │    │      (Secondary)          │   │   │
│  │                 │    │  - pvc-logs-sec     │    │                           │   │   │
│  │                 │    │  - pvc-backup-sec   │    │   ┌─────────────────────┐ │   │   │
│  └─────────────────┘    └─────────────────────┘    │   │ VolumeReplication   │ │   │   │
│                                                     │   │    (Secondary)      │ │   │   │
│                          ┌─────────────────────┐    │   └─────────────────────┘ │   │   │
│                          │VolumeGroupReplication│◀───┤                           │   │   │
│                          │      Content        │    │   ┌─────────────────────┐ │   │   │
│                          │   (Secondary)       │    │   │ CSI Driver +        │ │   │   │
│                          └─────────────────────┘    │   │ Replication Sidecar │ │   │   │
│                                                     └───┴─────────────────────┘ │   │   │
│                              Secondary Cluster                                   │   │   │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Custom Resource Definitions

### VolumeGroupReplicationClass

Defines the replication policy and parameters for volume group replication:

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeGroupReplicationClass
metadata:
  name: ceph-vgr-class
spec:
  # Must match the CSI driver's provisioner
  provisioner: openshift-storage.rbd.csi.ceph.com
  parameters:
    # Group replication mode
    mirroringMode: snapshot
    # Scheduling interval for group snapshots
    schedulingInterval: 1m
    # Group consistency settings
    clusterID: my-cluster
    # Secret for group replication credentials
    replication.storage.openshift.io/group-replication-secret-name: rook-csi-rbd-provisioner
    replication.storage.openshift.io/group-replication-secret-namespace: openshift-storage
```

### VolumeGroupReplication

Manages group replication state for multiple PVCs:

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeGroupReplication
metadata:
  name: database-group-replication
  namespace: database-app
spec:
  # Reference to the VolumeGroupReplicationClass
  volumeGroupReplicationClassName: ceph-vgr-class
  
  # Optional: VolumeReplicationClass for individual volume replications
  volumeReplicationClassName: ceph-vr-class
  
  # Optional: Name of the VolumeReplication CR created
  volumeReplicationName: database-volume-replication
  
  # Optional: Name of the VolumeGroupReplicationContent CR
  volumeGroupReplicationContentName: database-vgr-content
  
  # Desired replication state
  # - "primary": Volume group is the active primary
  # - "secondary": Volume group is a passive replica
  # - "resync": Trigger group resynchronization
  replicationState: primary
  
  # Auto-resync when in secondary state
  autoResync: false
  
  # External controller management
  external: false
  
  # Source: Label selector for PVCs to be grouped
  source:
    selector:
      matchLabels:
        app: database
        tier: storage
```

### VolumeGroupReplicationContent

Cluster-scoped resource containing volume grouping information:

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeGroupReplicationContent
metadata:
  name: database-vgr-content
spec:
  # Volume group attributes from CSI driver
  volumeGroupAttributes:
    clusterID: my-cluster
    consistencyGroupId: cg-001
  
  # Reference to the VolumeGroupReplication
  volumeGroupReplicationRef:
    kind: VolumeGroupReplication
    name: database-group-replication
    namespace: database-app
    uid: 12345678-1234-1234-1234-123456789abc
  
  # Unique group replication handle from CSI driver
  volumeGroupReplicationHandle: vgr-handle-001
  
  # CSI driver provisioner name
  provisioner: openshift-storage.rbd.csi.ceph.com
  
  # VolumeGroupReplicationClass name
  volumeGroupReplicationClassName: ceph-vgr-class
  
  # Source: List of volume handles in the group
  source:
    volumeHandles:
      - pv-data-handle-001
      - pv-logs-handle-002
      - pv-backup-handle-003

status:
  # List of PVs in the group replication
  persistentVolumeRefList:
    - name: pv-database-data
    - name: pv-database-logs  
    - name: pv-database-backup
```

---

## Volume Group Replication Status

The VolumeGroupReplication status reflects the collective state of all volumes in the group:

```yaml
status:
  # Overall group replication state
  state: Primary  # Primary, Secondary, Resyncing, Unknown
  
  # Human-readable message
  message: "Volume group is primary and all volumes are healthy"
  
  # Conditions for detailed status
  conditions:
    - type: Completed
      status: "True"
      reason: Promoted
      message: "Volume group promoted to primary"
      lastTransitionTime: "2024-01-15T10:30:00Z"
    
    - type: Degraded
      status: "False"
      reason: Healthy
      message: "All volumes in group are synchronized"
    
    - type: Resyncing
      status: "False"
      reason: NotResyncing
      message: "No group resync in progress"
    
    - type: Replicating
      status: "True"
      reason: GroupReplicating
      message: "Volume group is actively replicating"
  
  # Group replication metrics
  lastSyncTime: "2024-01-15T10:29:00Z"
  lastSyncDuration: "5s"
  lastSyncBytes: 10485760
  
  # List of PVCs in the group replication
  persistentVolumeClaimsRefList:
    - name: pvc-database-data
    - name: pvc-database-logs
    - name: pvc-database-backup
```

---

## Volume Group Replication Operations

### Core Group Operations

| Operation | Description | Scope |
|-----------|-------------|-------|
| `EnableVolumeReplication` | Enables replication for volume group | Entire group |
| `DisableVolumeReplication` | Disables replication for volume group | Entire group |
| `PromoteVolume` | Promotes group to primary | Entire group |
| `DemoteVolume` | Demotes group to secondary | Entire group |
| `ResyncVolume` | Resynchronizes volume group data | Entire group |
| `GetVolumeReplicationInfo` | Gets group replication status | Entire group |

### CLI Usage for Volume Groups

```bash
# Enable group replication
kubectl exec -c csi-addons <pod> -- csi-addons \
  -operation EnableVolumeReplication \
  -volumegroupid <volume-group-id> \
  -parameters mirroringMode=snapshot,schedulingInterval=1m

# Get group replication status
kubectl exec -c csi-addons <pod> -- csi-addons \
  -operation GetVolumeReplicationInfo \
  -volumegroupid <volume-group-id>

# Promote group to primary
kubectl exec -c csi-addons <pod> -- csi-addons \
  -operation PromoteVolume \
  -volumegroupid <volume-group-id>

# Demote group to secondary
kubectl exec -c csi-addons <pod> -- csi-addons \
  -operation DemoteVolume \
  -volumegroupid <volume-group-id>

# Resync group after failover
kubectl exec -c csi-addons <pod> -- csi-addons \
  -operation ResyncVolume \
  -volumegroupid <volume-group-id>

# Disable group replication
kubectl exec -c csi-addons <pod> -- csi-addons \
  -operation DisableVolumeReplication \
  -volumegroupid <volume-group-id>
```

---

## Volume Group Replication Workflows

### Workflow 1: Group Setup

Enable replication for a group of related PVCs:

```
┌─────────────────────────────┐
│  1. Create multiple PVCs     │
│     with matching labels     │
│     (app=database)           │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  2. Create                  │
│  VolumeGroupReplication CR  │
│  with label selector        │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  3. Controller identifies   │
│  matching PVCs and creates  │
│  VolumeGroupReplicationContent │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  4. Controller calls        │
│  EnableVolumeReplication    │
│  for the volume group       │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  5. CSI driver creates      │
│  consistency group and      │
│  enables group mirroring    │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  6. Status updated to       │
│  Primary with all PVC refs  │
└─────────────────────────────┘
```

### Workflow 2: Group Failover

Failover entire application with multiple volumes:

```
Primary Cluster                         Secondary Cluster
─────────────────                       ──────────────────

┌─────────────────┐
│ 1. Stop/Scale   │
│    Application  │
│    to 0 replicas│
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 2. Wait for     │
│    group sync   │
│    completion   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 3. Demote       │
│    entire group │
│    to secondary │ ─────────────────────────▶ ┌─────────────────┐
└─────────────────┘                            │ 4. Promote      │
                                               │    entire group │
                                               │    to primary   │
                                               └────────┬────────┘
                                                        │
                                                        ▼
                                               ┌─────────────────┐
                                               │ 5. Update app   │
                                               │    deployment   │
                                               │    PVC refs     │
                                               └────────┬────────┘
                                                        │
                                                        ▼
                                               ┌─────────────────┐
                                               │ 6. Start        │
                                               │    Application  │
                                               └─────────────────┘
```

### Workflow 3: Disaster Recovery (Group)

Recover complete application stack from secondary site:

```
Primary Cluster (FAILED)                Secondary Cluster
────────────────────────               ──────────────────

     ╳ Site Down ╳                     ┌─────────────────┐
                                       │ 1. Detect       │
                                       │    site failure │
                                       └────────┬────────┘
                                                │
                                                ▼
                                       ┌─────────────────┐
                                       │ 2. Force        │
                                       │    promote      │
                                       │    volume group │
                                       └────────┬────────┘
                                                │
                                                ▼
                                       ┌─────────────────┐
                                       │ 3. Update       │
                                       │    application  │
                                       │    PVC bindings │
                                       └────────┬────────┘
                                                │
                                                ▼
                                       ┌─────────────────┐
                                       │ 4. Start        │
                                       │    Application  │
                                       │    Stack        │
                                       └─────────────────┘
```

### Workflow 4: Group Failback

Return complete application to original site:

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
│ 2. Create new   │                    │ 3. Stop         │
│    secondary    │◀───────────────────│    Application  │
│    volume group │                    └────────┬────────┘
└────────┬────────┘                             │
         │                                      ▼
         ▼                             ┌─────────────────┐
┌─────────────────┐                    │ 4. Trigger      │
│ 5. Resync       │◀───────────────────│    group resync │
│    volume group │                    └─────────────────┘
└────────┬────────┘
         │
         ▼
┌─────────────────┐                    ┌─────────────────┐
│ 6. Wait for     │                    │ 7. Demote       │
│    group sync   │                    │    group to     │
│    complete     │                    │    secondary    │
└────────┬────────┘                    └────────┬────────┘
         │                                      │
         ▼                                      ▼
┌─────────────────┐
│ 8. Promote      │◀───────────────────────────┘
│    group to     │
│    primary      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 9. Start        │
│    Application  │
│    Stack        │
└─────────────────┘
```

---

## Volume Group Management

### Creating a Volume Group

1. **Label your PVCs consistently:**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-data
  namespace: database-app
  labels:
    app: database
    tier: storage
    component: data
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 100Gi
  storageClassName: ceph-rbd

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-logs
  namespace: database-app
  labels:
    app: database
    tier: storage
    component: logs
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 50Gi
  storageClassName: ceph-rbd

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-backup
  namespace: database-app
  labels:
    app: database
    tier: storage
    component: backup
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 200Gi
  storageClassName: ceph-rbd
```

2. **Create VolumeGroupReplicationClass:**

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeGroupReplicationClass
metadata:
  name: database-vgr-class
spec:
  provisioner: openshift-storage.rbd.csi.ceph.com
  parameters:
    mirroringMode: snapshot
    schedulingInterval: 1m
    clusterID: my-cluster
    replication.storage.openshift.io/group-replication-secret-name: rook-csi-rbd-provisioner
    replication.storage.openshift.io/group-replication-secret-namespace: openshift-storage
```

3. **Create VolumeGroupReplication:**

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeGroupReplication
metadata:
  name: database-group-replication
  namespace: database-app
spec:
  volumeGroupReplicationClassName: database-vgr-class
  replicationState: primary
  source:
    selector:
      matchLabels:
        app: database
        tier: storage
```

### Monitoring Group Status

```bash
# Check VolumeGroupReplication status
kubectl get volumegroupreplication database-group-replication -n database-app -o yaml

# List all PVCs in the group
kubectl get volumegroupreplication database-group-replication -n database-app \
  -o jsonpath='{.status.persistentVolumeClaimsRefList[*].name}'

# Check individual volume replication status
kubectl get volumereplication database-volume-replication -n database-app
```

---

## Supported Storage Backends

| Storage Backend | Group Support | Notes |
|-----------------|---------------|--------|
| **Ceph RBD** | ✅ Yes | Consistency groups via RBD mirroring |
| **NetApp ONTAP** | ✅ Yes | SnapMirror consistency groups |
| **Dell PowerStore** | ✅ Yes | Replication sessions with consistency |
| **Pure Storage** | ✅ Yes | ActiveCluster pod consistency |
| **IBM Spectrum Scale** | ⚠️ Partial | AFM-based group replication |
| **Dell PowerScale** | ✅ Yes | SyncIQ policy groups |

---

## Best Practices

### 1. Label Strategy

Use consistent labeling for PVCs that should be grouped:

```yaml
metadata:
  labels:
    app: my-application
    tier: storage
    consistency-group: app-cg-1
```

### 2. Resource Limits

- Maximum 100 PVCs per VolumeGroupReplication
- Consider network bandwidth for large groups
- Plan for consistent snapshot window timing

### 3. Application Consistency

```yaml
spec:
  # Enable auto-resync for automatic recovery
  autoResync: true
  
  # Use appropriate scheduling for app consistency
  parameters:
    schedulingInterval: 5m  # Based on app write patterns
```

### 4. Monitoring Setup

```yaml
# Alert on group degradation
- alert: VolumeGroupReplicationDegraded
  expr: csi_addons_volumegroupreplication_state{state="degraded"} == 1
  for: 5m
  
# Alert on group sync issues  
- alert: VolumeGroupReplicationSyncStale
  expr: time() - csi_addons_volumegroupreplication_last_sync_time > 900
  for: 5m
```

---

## Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| `PVC not found in selector` | Label mismatch | Verify PVC labels match selector |
| `Group size exceeds limit` | Too many PVCs | Split into multiple groups (max 100) |
| `Inconsistent group state` | Partial failure | Check individual volume status |
| `Group resync stuck` | Network/storage issue | Check connectivity and force resync |

### Debug Commands

```bash
# Check group composition
kubectl get vgr database-group-replication -o jsonpath='{.status.persistentVolumeClaimsRefList}'

# Verify selector matching
kubectl get pvc -l app=database,tier=storage

# Check VolumeGroupReplicationContent
kubectl get volumegroupreplicationcontent

# Inspect group replication logs
kubectl logs -n csi-system <csi-addons-controller-pod>
```

### Recovery Procedures

**Split-brain scenario:**
```bash
# Force promote secondary (data loss risk)
kubectl patch volumegroupreplication database-group-replication \
  --type=merge -p='{"spec":{"replicationState":"primary"}}'

# Wait for controller to process
kubectl wait --for=condition=Completed volumegroupreplication/database-group-replication
```

---

## References

- [CSI Addons Volume Group Replication Types](https://github.com/csi-addons/kubernetes-csi-addons/blob/main/api/replication.storage/v1alpha1/volumegroupreplication_types.go)
- [Volume Group Replication Class Types](https://github.com/csi-addons/kubernetes-csi-addons/blob/main/api/replication.storage/v1alpha1/volumegroupreplicationclass_types.go)
- [Volume Group Replication Content Types](https://github.com/csi-addons/kubernetes-csi-addons/blob/main/api/replication.storage/v1alpha1/volumegroupreplicationcontent_types.go)
- [Volume Group Replication Design Document](https://github.com/csi-addons/kubernetes-csi-addons/blob/main/docs/design/volumegroupreplication.md)
- [CSI Addons Main Documentation](https://github.com/csi-addons/kubernetes-csi-addons)