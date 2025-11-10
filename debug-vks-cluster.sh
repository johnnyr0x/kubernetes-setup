#!/bin/bash

# Script to debug VKS cluster provisioning issues
# Usage: ./debug-vks-cluster.sh <cluster-name> [namespace]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Get cluster name and namespace
CLUSTER_NAME="${1}"
NAMESPACE="${2:-dev-wrcc9}"

if [ -z "$CLUSTER_NAME" ]; then
    print_error "Usage: $0 <cluster-name> [namespace]"
    exit 1
fi

print_header "VKS Cluster Debug Report: $CLUSTER_NAME"
echo "Namespace: $NAMESPACE"
echo "Timestamp: $(date)"

# 1. Cluster Status
print_header "1. Cluster Status"
kubectl get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o wide || print_error "Failed to get cluster"

# 2. Cluster Conditions
print_header "2. Cluster Conditions (Failures Only)"
kubectl get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{range .status.conditions[?(@.status=="False")]}{.type}{"\t"}{.reason}{"\t"}{.message}{"\n"}{end}' | column -t -s $'\t' || true

# 3. Machine Status
print_header "3. Machines Status"
kubectl get machines -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o wide

# 4. Machine Details and Issues
print_header "4. Machine Health Issues"
for machine in $(kubectl get machines -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o jsonpath='{.items[*].metadata.name}'); do
    echo ""
    echo "--- Machine: $machine ---"
    kubectl get machine "$machine" -n "$NAMESPACE" -o jsonpath='Status: {.status.phase}{"\n"}Ready: {.status.ready}{"\n"}NodeRef: {.status.nodeRef.name}{"\n"}ProviderID: {.status.providerID}{"\n"}'
    
    # Show conditions with issues
    echo "Conditions with issues:"
    kubectl get machine "$machine" -n "$NAMESPACE" -o jsonpath='{range .status.conditions[?(@.status!="True")]}{.type}: {.reason} - {.message}{"\n"}{end}' || true
done

# 5. vSphere Machines
print_header "5. vSphere Machine Resources"
kubectl get vspheremachine -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o wide || print_warning "No vSphere machines found or access denied"

# 6. vSphere Machine Details
print_header "6. vSphere Machine Details & Issues"
for vsmachine in $(kubectl get vspheremachine -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""); do
    if [ -n "$vsmachine" ]; then
        echo ""
        echo "--- vSphereMachine: $vsmachine ---"
        kubectl describe vspheremachine "$vsmachine" -n "$NAMESPACE" | grep -A 30 "Status:\|Events:"
    fi
done

# 7. Control Plane Status
print_header "7. Control Plane Status"
kubectl get kubeadmcontrolplane -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o wide || print_warning "No control plane found"

# 8. Machine Deployments
print_header "8. Machine Deployments (Workers)"
kubectl get machinedeployment -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o wide || print_warning "No machine deployments found"

# 9. Recent Events
print_header "9. Recent Events (Last 20)"
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | grep "$CLUSTER_NAME" | tail -20 || print_warning "No events found"

# 10. CAPV Controller Logs
print_header "10. CAPV Controller Errors (Last 50 lines)"
kubectl logs -n vmware-system-capv deployment/capv-controller-manager --tail=50 | grep -i "error\|failed\|$CLUSTER_NAME" || print_info "No recent errors in CAPV logs"

# 11. vSphere Cluster Info
print_header "11. vSphere Cluster Resource"
kubectl get vspherecluster -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o yaml || print_warning "Cannot get vSphere cluster info"

# 12. Diagnostic Summary
print_header "12. Diagnostic Summary"
echo ""
print_info "Common Issues to Check:"
echo "  1. vSphere Resources:"
echo "     - Check vCenter for VMs with the cluster name"
echo "     - Verify sufficient CPU, memory, and storage"
echo "     - Check datastore capacity"
echo ""
echo "  2. Network Configuration:"
echo "     - Verify DHCP is working"
echo "     - Check network port group accessibility"
echo "     - Ensure DNS resolution works"
echo ""
echo "  3. Content Library:"
echo "     - Verify OS image template is accessible"
echo "     - Check content library permissions"
echo ""
echo "  4. Credentials & Permissions:"
echo "     - Verify vSphere credentials are valid"
echo "     - Check service account has VM creation permissions"
echo "     - Verify resource pool access"
echo ""
echo "  5. Review the output above for specific error messages"
echo ""

print_header "Debug Report Complete"
print_info "Save this output and share with your vSphere admin if infrastructure issues are found"

