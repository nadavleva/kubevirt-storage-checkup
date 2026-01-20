# AWS GPFS Playground - KVM Virtualization Setup

This document provides instructions for modifying the [aws-ibm-gpfs-playground](https://github.com/openshift-storage-scale/aws-ibm-gpfs-playground/tree/hitachi-setup) project to enable KVM virtualization support for running the full CSI certification test suite.

## Problem Statement

The default aws-ibm-gpfs-playground configuration uses `m5.2xlarge` worker instances which **do not support KVM virtualization**. This causes VM-based tests (8-17) to fail with:

```
0/6 nodes are available: 3 Insufficient devices.kubevirt.io/kvm
```

## Solution

Change the worker instance type from `m5.2xlarge` to a `.metal` instance type that supports bare-metal virtualization.

---

## AI Agent Instructions

The following instructions are for an AI coding agent to modify the aws-ibm-gpfs-playground project:

### Task: Enable KVM Support for CSI Certification Testing

**Repository:** https://github.com/openshift-storage-scale/aws-ibm-gpfs-playground  
**Branch:** `hitachi-setup`

### Step 1: Locate Instance Type Configuration

Search for files containing worker instance type configuration:

```bash
# Search for instance type settings
grep -r "worker.*type\|instance_type\|ocp_worker_type" --include="*.yml" --include="*.yaml"
grep -r "m5.2xlarge\|m5\..*xlarge" --include="*.yml" --include="*.yaml"
```

Expected locations:
- `group_vars/all` or `group_vars/all.yml`
- `vars/main.yml`
- `overrides.yml.example` or similar template files

### Step 2: Identify the Variable

Look for variables like:
- `ocp_worker_type`
- `worker_instance_type`
- `aws_instance_type`

The current value is likely: `m5.2xlarge`

### Step 3: Change Worker Instance Type

Update the default worker instance type to a metal instance:

**Option A: Change default in group_vars/all**

```yaml
# Before
ocp_worker_type: "m5.2xlarge"

# After - for KVM/virtualization support (cost-optimized)
ocp_worker_type: "m5zn.metal"
```

**Option B: Add new variable for virtualization workloads**

```yaml
# Standard worker type (storage testing only)
ocp_worker_type: "m5.2xlarge"

# Virtualization-enabled worker type (for CNV/KVM testing)
ocp_worker_type_metal: "m5zn.metal"

# Flag to enable virtualization support
enable_virtualization: false
```

Then update the playbook to use conditional logic:

```yaml
worker_type: "{{ ocp_worker_type_metal if enable_virtualization | default(false) else ocp_worker_type }}"
```

### Step 4: Update Documentation

Add a note to the README.md about virtualization requirements:

```markdown
## Virtualization Support (CNV/KVM Testing)

To run workloads that require KVM virtualization (e.g., OpenShift Virtualization, KubeVirt):

1. Set metal instance type in `overrides.yml`:
   ```yaml
   ocp_worker_type: "m5.metal"
   ```

2. Or enable the virtualization flag:
   ```yaml
   enable_virtualization: true
   ```

> **Note:** Metal instances are significantly more expensive. Use only when virtualization testing is required.

### Metal Instance Comparison

| Instance Type | vCPUs | Memory | Cost/hr (approx) |
|---------------|-------|--------|------------------|
| m5.2xlarge    | 8     | 32 GiB | ~$0.38          |
| m5.metal      | 96    | 384 GiB| ~$4.60          |
| m5zn.metal    | 48    | 192 GiB| ~$3.96          |
```

### Step 5: Add Makefile Target (Optional)

Add a new make target for virtualization-enabled deployment:

```makefile
# Deploy with virtualization support (metal instances)
install-with-virtualization:
	EXTRA_VARS="-e ocp_worker_type=m5.metal" $(MAKE) install
```

---

## Recommended Metal Instance Types

| Instance Type | vCPUs | Memory | Network | Cost/hr | Best For |
|---------------|-------|--------|---------|---------|----------|
| **`m5zn.metal`** | 48 | 192 GiB | 100 Gbps | ~$3.96 | **Recommended** - best cost/performance |
| `c5.metal` | 96 | 192 GiB | 25 Gbps | ~$4.08 | Compute-intensive workloads |
| `m5.metal` | 96 | 384 GiB | 25 Gbps | ~$4.60 | Large memory workloads |
| `m5n.metal` | 96 | 384 GiB | 100 Gbps | ~$4.77 | High network throughput |
| `r5.metal` | 96 | 768 GiB | 25 Gbps | ~$6.05 | Memory-intensive workloads |
| `i3.metal` | 72 | 512 GiB | 25 Gbps | ~$4.99 | Storage-optimized with NVMe |

### Region Availability

Not all metal instances are available in all regions. Check availability:

```bash
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters Name=instance-type,Values=m5zn.metal \
  --region eu-north-1 \
  --query 'InstanceTypeOfferings[*].Location' \
  --output table
```

---

## Cost Considerations

| Configuration | Instance Type | Workers | Estimated Cost/hr |
|---------------|---------------|---------|-------------------|
| Storage Only | m5.2xlarge | 3 | ~$1.14 |
| With Virtualization | m5zn.metal | 3 | ~$11.88 |
| With Virtualization | m5.metal | 3 | ~$13.80 |

> **Tip:** For cost savings, consider using a single metal worker node for virtualization testing, or use Spot instances if your testing is fault-tolerant.

---

## Verification After Deployment

After deploying with metal instances, verify KVM support:

```bash
# Check for KVM device on worker nodes
oc debug node/<worker-node-name> -- chroot /host ls -la /dev/kvm

# Check kubevirt node labels
oc get nodes -l kubevirt.io/schedulable=true -o wide

# Verify no KVM-related scheduling issues
oc get pods -A | grep virt-launcher
```

---

## Files to Modify Summary

| File | Change |
|------|--------|
| `group_vars/all` | Change `ocp_worker_type` default |
| `README.md` | Add virtualization documentation |
| `overrides.yml.example` | Add example for metal instances |
| `Makefile` | Add optional `install-with-virtualization` target |

---

## References

- [AWS EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)
- [OpenShift Virtualization Requirements](https://docs.openshift.com/container-platform/latest/virt/install/preparing-cluster-for-virt.html)
- [KubeVirt Node Requirements](https://kubevirt.io/user-guide/operations/installation/#requirements)
- [aws-ibm-gpfs-playground](https://github.com/openshift-storage-scale/aws-ibm-gpfs-playground/tree/hitachi-setup)

