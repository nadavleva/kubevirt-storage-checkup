#!/bin/bash
# Run KubeVirt Storage Checkup E2E tests against aws-gpfs-playground cluster
#
# Usage: ./scripts/run-e2e-gpfs.sh [namespace]
#
# Prerequisites:
# - aws-gpfs-playground cluster is running
# - kubeconfig is available at ~/aws-gpfs-playground/ocp_install_files/auth/kubeconfig

set -euo pipefail

# Configuration
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/aws-gpfs-playground/ocp_install_files/auth/kubeconfig}"
CHECKUP_NAMESPACE="${1:-storage-checkup-test}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if [[ ! -f "$KUBECONFIG_PATH" ]]; then
        log_error "Kubeconfig not found at: $KUBECONFIG_PATH"
        log_error "Make sure the aws-gpfs-playground cluster is deployed"
        exit 1
    fi
    
    export KUBECONFIG="$KUBECONFIG_PATH"
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to cluster. Check kubeconfig at: $KUBECONFIG_PATH"
        exit 1
    fi
    
    log_info "Connected to cluster: $(kubectl cluster-info | head -1)"
}

# Check cluster capabilities
check_cluster_capabilities() {
    log_info "Checking cluster capabilities..."
    
    # Check node count
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    log_info "Cluster has $NODE_COUNT node(s)"
    
    if [[ $NODE_COUNT -lt 2 ]]; then
        log_warn "Single-node cluster detected. Live migration test will be skipped."
    fi
    
    # Check for CNV (OpenShift Virtualization)
    if kubectl get crd virtualmachines.kubevirt.io &> /dev/null; then
        log_info "OpenShift Virtualization (CNV) is installed"
        CNV_INSTALLED=true
    else
        log_warn "OpenShift Virtualization (CNV) is NOT installed"
        log_warn "VM-based tests (8-17) will fail or be skipped"
        CNV_INSTALLED=false
    fi
    
    # Check storage classes
    log_info "Available storage classes:"
    kubectl get storageclasses -o custom-columns=NAME:.metadata.name,PROVISIONER:.provisioner,DEFAULT:.metadata.annotations."storageclass\.kubernetes\.io/is-default-class"
    echo ""
}

# Setup namespace and permissions
setup_permissions() {
    log_info "Setting up namespace and permissions..."
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$CHECKUP_NAMESPACE" &> /dev/null; then
        kubectl create namespace "$CHECKUP_NAMESPACE"
        log_info "Created namespace: $CHECKUP_NAMESPACE"
    else
        log_info "Namespace already exists: $CHECKUP_NAMESPACE"
    fi
    
    # Apply permissions
    kubectl apply -n "$CHECKUP_NAMESPACE" -f "$PROJECT_DIR/manifests/storage_checkup_permissions.yaml"
    log_info "Applied storage checkup permissions"
    
    # Create cluster-reader binding
    cat <<EOF | kubectl apply -f -
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
  namespace: $CHECKUP_NAMESPACE
EOF
    log_info "Applied cluster-reader binding"
}

# Run the checkup
run_checkup() {
    log_info "Running storage checkup..."
    
    # Delete existing job if present
    kubectl delete job storage-checkup -n "$CHECKUP_NAMESPACE" --ignore-not-found=true
    kubectl delete configmap storage-checkup-config -n "$CHECKUP_NAMESPACE" --ignore-not-found=true
    
    # Apply checkup
    export CHECKUP_NAMESPACE
    envsubst < "$PROJECT_DIR/manifests/storage_checkup.yaml" | kubectl apply -f -
    
    log_info "Waiting for checkup job to complete..."
    
    # Wait for job completion (timeout 15 minutes)
    if kubectl wait --for=condition=complete job/storage-checkup -n "$CHECKUP_NAMESPACE" --timeout=900s 2>/dev/null; then
        log_info "Checkup completed successfully!"
    else
        if kubectl wait --for=condition=failed job/storage-checkup -n "$CHECKUP_NAMESPACE" --timeout=10s 2>/dev/null; then
            log_error "Checkup job failed!"
        else
            log_warn "Checkup job timed out or status unknown"
        fi
    fi
}

# Get results
get_results() {
    log_info "Retrieving results..."
    echo ""
    echo "=========================================="
    echo "         CHECKUP RESULTS                 "
    echo "=========================================="
    
    kubectl get configmap storage-checkup-config -n "$CHECKUP_NAMESPACE" -o yaml
    
    echo ""
    echo "=========================================="
    echo "         CHECKUP LOGS                    "
    echo "=========================================="
    kubectl logs -n "$CHECKUP_NAMESPACE" job/storage-checkup --tail=100
}

# Cleanup
cleanup() {
    log_info "Cleaning up..."
    
    export CHECKUP_NAMESPACE
    envsubst < "$PROJECT_DIR/manifests/storage_checkup.yaml" | kubectl delete -f - --ignore-not-found=true
    kubectl delete clusterrolebinding kubevirt-storage-checkup-clustereader --ignore-not-found=true
    
    read -p "Delete namespace $CHECKUP_NAMESPACE? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete namespace "$CHECKUP_NAMESPACE" --ignore-not-found=true
        log_info "Namespace deleted"
    fi
    
    log_info "Cleanup complete"
}

# Main
main() {
    echo "=========================================="
    echo "  KubeVirt Storage Checkup E2E Tests    "
    echo "=========================================="
    echo ""
    
    check_prerequisites
    check_cluster_capabilities
    
    echo ""
    read -p "Continue with test execution? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Aborted by user"
        exit 0
    fi
    
    setup_permissions
    run_checkup
    get_results
    
    echo ""
    read -p "Run cleanup? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup
    else
        log_info "Skipping cleanup. To clean up later, run:"
        echo "  export KUBECONFIG=$KUBECONFIG_PATH"
        echo "  export CHECKUP_NAMESPACE=$CHECKUP_NAMESPACE"
        echo "  envsubst < manifests/storage_checkup.yaml | kubectl delete -f -"
        echo "  kubectl delete clusterrolebinding kubevirt-storage-checkup-clustereader"
        echo "  kubectl delete namespace $CHECKUP_NAMESPACE"
    fi
}

# Handle arguments
case "${1:-}" in
    --cleanup)
        export KUBECONFIG="$KUBECONFIG_PATH"
        CHECKUP_NAMESPACE="${2:-storage-checkup-test}"
        cleanup
        ;;
    --results)
        export KUBECONFIG="$KUBECONFIG_PATH"
        CHECKUP_NAMESPACE="${2:-storage-checkup-test}"
        get_results
        ;;
    --help|-h)
        echo "Usage: $0 [namespace] [options]"
        echo ""
        echo "Options:"
        echo "  --cleanup [namespace]   Clean up resources"
        echo "  --results [namespace]   Get results only"
        echo "  --help, -h              Show this help"
        echo ""
        echo "Environment variables:"
        echo "  KUBECONFIG              Path to kubeconfig (default: ~/aws-gpfs-playground/ocp_install_files/auth/kubeconfig)"
        exit 0
        ;;
    *)
        main
        ;;
esac

