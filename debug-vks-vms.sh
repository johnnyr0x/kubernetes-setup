#!/bin/bash

# Script to debug VKS VM-level issues
# Usage: ./debug-vks-vms.sh <cluster-name> [namespace]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_subheader() {
    echo ""
    echo -e "${CYAN}--- $1 ---${NC}"
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

print_header "VKS VM-Level Debug Report: $CLUSTER_NAME"
echo "Namespace: $NAMESPACE"
echo "Timestamp: $(date)"

# 1. Get all VMs for this cluster
print_header "1. Virtual Machines Status"
kubectl get virtualmachine -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o wide

# 2. Get VM details with IP addresses
print_header "2. VM Network and Power Status"
echo ""
for vm in $(kubectl get virtualmachine -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o jsonpath='{.items[*].metadata.name}'); do
    print_subheader "VM: $vm"
    
    echo "Power State:"
    kubectl get virtualmachine "$vm" -n "$NAMESPACE" -o jsonpath='  {.status.powerState}{"\n"}' 2>/dev/null || echo "  N/A"
    
    echo "VM Tools Status:"
    kubectl get virtualmachine "$vm" -n "$NAMESPACE" -o jsonpath='  {.status.vmToolsStatus}{"\n"}' 2>/dev/null || echo "  N/A"
    
    echo "IP Addresses:"
    kubectl get virtualmachine "$vm" -n "$NAMESPACE" -o jsonpath='{range .status.network.interfaces[*]}  Interface: {.name}, IP: {.ip.addresses[0].address}{"\n"}{end}' 2>/dev/null || echo "  N/A"
    
    echo "VM IP (from vSphereMachine):"
    kubectl get vspheremachine -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o jsonpath="{range .items[?(@.metadata.name=='$vm')]}{.status.addresses[0].address}{end}" 2>/dev/null || echo "  N/A"
    echo ""
done

# 3. Detailed VM status
print_header "3. Detailed VM Configuration and Status"
for vm in $(kubectl get virtualmachine -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o jsonpath='{.items[*].metadata.name}'); do
    print_subheader "VM Details: $vm"
    kubectl describe virtualmachine "$vm" -n "$NAMESPACE" | grep -A 100 "Status:" || print_warning "Could not get detailed status"
    echo ""
done

# 4. Check bootstrap secrets
print_header "4. Bootstrap Configuration Secrets"
echo ""
for machine in $(kubectl get machines -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o jsonpath='{.items[*].metadata.name}'); do
    print_subheader "Machine: $machine"
    
    # Check if secret exists
    if kubectl get secret "$machine" -n "$NAMESPACE" &>/dev/null; then
        print_success "Bootstrap secret exists"
        echo "Secret size (bytes):"
        kubectl get secret "$machine" -n "$NAMESPACE" -o jsonpath='{.data.value}' | wc -c
        
        # Check for common cloud-init issues
        echo ""
        echo "Checking cloud-init data for common issues:"
        bootstrap_data=$(kubectl get secret "$machine" -n "$NAMESPACE" -o jsonpath='{.data.value}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        
        if echo "$bootstrap_data" | grep -q "kubeadm join"; then
            print_success "Contains 'kubeadm join' command"
        else
            print_warning "Does NOT contain 'kubeadm join' command (might be control plane)"
        fi
        
        if echo "$bootstrap_data" | grep -q "apiserver"; then
            print_success "Contains 'apiserver' reference"
        fi
        
        if echo "$bootstrap_data" | grep -q "certificate-key"; then
            print_success "Contains certificate key"
        fi
    else
        print_error "Bootstrap secret NOT found for $machine"
    fi
    echo ""
done

# 5. Machine health and conditions
print_header "5. Machine Health Conditions"
for machine in $(kubectl get machines -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o jsonpath='{.items[*].metadata.name}'); do
    print_subheader "Machine: $machine"
    kubectl get machine "$machine" -n "$NAMESPACE" -o jsonpath='Phase: {.status.phase}{"\n"}Ready: {.status.ready}{"\n"}NodeRef: {.status.nodeRef.name}{"\n"}{"\n"}Conditions:{"\n"}{range .status.conditions[*]}{.type}: {.status} - {.reason} - {.message}{"\n"}{end}' || print_error "Failed to get machine status"
    echo ""
done

# 6. Recent events for VMs
print_header "6. Recent VM Events (Last 30)"
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | grep "$CLUSTER_NAME" | grep -i "virtual\|vm\|unhealthy\|failed" | tail -30 || print_warning "No VM-related events found"

# 7. Control plane endpoint connectivity
print_header "7. Control Plane Endpoint Connectivity Test"
CONTROL_PLANE_IP=$(kubectl get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.controlPlaneEndpoint.host}' 2>/dev/null)
CONTROL_PLANE_PORT=$(kubectl get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.controlPlaneEndpoint.port}' 2>/dev/null)

if [ -n "$CONTROL_PLANE_IP" ]; then
    echo "Control Plane Endpoint: $CONTROL_PLANE_IP:$CONTROL_PLANE_PORT"
    echo ""
    echo "Testing connectivity from management cluster:"
    if timeout 5 nc -zv "$CONTROL_PLANE_IP" "$CONTROL_PLANE_PORT" 2>&1; then
        print_success "Can reach control plane endpoint from management cluster"
    else
        print_error "Cannot reach control plane endpoint from management cluster"
    fi
else
    print_warning "Could not determine control plane endpoint"
fi

# 8. Image information
print_header "8. VM Image Information"
for vspheremachine in $(kubectl get vspheremachine -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o jsonpath='{.items[*].metadata.name}'); do
    print_subheader "vSphereMachine: $vspheremachine"
    echo "Image Name:"
    kubectl get vspheremachine "$vspheremachine" -n "$NAMESPACE" -o jsonpath='  {.spec.imageName}{"\n"}' || echo "  N/A"
    
    echo "Storage Class:"
    kubectl get vspheremachine "$vspheremachine" -n "$NAMESPACE" -o jsonpath='  {.spec.storageClass}{"\n"}' || echo "  N/A"
    
    echo "VM Class:"
    kubectl get vspheremachine "$vspheremachine" -n "$NAMESPACE" -o jsonpath='  {.spec.className}{"\n"}' || echo "  N/A"
    echo ""
done

# 9. Generate SSH/Console Access Commands
print_header "9. VM Access Information"
echo ""

# Get the SSH password for the cluster
print_info "Retrieving SSH password for cluster VMs..."
SSH_PASSWORD=$(kubectl get secret "${CLUSTER_NAME}-ssh-password" -n "$NAMESPACE" -o jsonpath='{.data.ssh-passwordkey}' 2>/dev/null | base64 -d 2>/dev/null)

if [ -n "$SSH_PASSWORD" ]; then
    print_success "SSH password found"
    echo ""
    echo "Login Credentials for VMs:"
    echo "  Username: vmware-system-user"
    echo "  Password: $SSH_PASSWORD"
    echo ""
    print_info "After login, become root with: sudo su -"
else
    print_warning "Could not retrieve SSH password"
    echo "To get the password manually, run:"
    echo "  kubectl get secret ${CLUSTER_NAME}-ssh-password -n $NAMESPACE -o jsonpath='{.data.ssh-passwordkey}' | base64 -d"
fi

echo ""
print_info "Attempting to collect logs from VMs via SSH..."
echo ""

# Try to find SSH key
SSH_KEY=""
for key in ~/.ssh/id_rsa ~/.ssh/id_ed25519 ~/.ssh/id_ecdsa; do
    if [ -f "$key" ]; then
        # Test if this key works by checking the public key
        pub_key=$(ssh-keygen -y -f "$key" 2>/dev/null || echo "")
        # We'd need to compare with the authorized key from the secret, but for now just use first found key
        SSH_KEY="$key"
        break
    fi
done

if [ -n "$SSH_KEY" ]; then
    print_info "Found SSH key: $SSH_KEY"
    print_info "Attempting automated log collection..."
else
    print_warning "No SSH key found. Will provide manual access instructions."
fi

echo ""
print_info "VM Access and Diagnostics:"
echo ""

for vm in $(kubectl get virtualmachine -n "$NAMESPACE" -l cluster.x-k8s.io/cluster-name="$CLUSTER_NAME" -o jsonpath='{.items[*].metadata.name}'); do
    vm_ip=$(kubectl get vspheremachine "$vm" -n "$NAMESPACE" -o jsonpath='{.status.addresses[0].address}' 2>/dev/null)
    
    if [ -n "$vm_ip" ]; then
        print_subheader "VM: $vm (IP: $vm_ip)"
        
        # Try automated SSH if key is available
        if [ -n "$SSH_KEY" ]; then
            if timeout 5 ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 vmware-system-user@"$vm_ip" "echo SSH_OK" &>/dev/null; then
                print_success "SSH connection successful! Collecting logs..."
                
                echo ""
                echo "=== Cloud-init Status ==="
                ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no vmware-system-user@"$vm_ip" "cloud-init status" 2>/dev/null || echo "Failed to get cloud-init status"
                
                echo ""
                echo "=== Kubelet Status ==="
                ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no vmware-system-user@"$vm_ip" "sudo systemctl status kubelet --no-pager | head -20" 2>/dev/null || echo "Failed to get kubelet status"
                
                echo ""
                echo "=== Recent Kubelet Errors ==="
                ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no vmware-system-user@"$vm_ip" "sudo journalctl -u kubelet -n 20 --no-pager | grep -i error" 2>/dev/null || echo "No recent kubelet errors or failed to retrieve"
                
                echo ""
                echo "=== CNI Configuration ==="
                ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no vmware-system-user@"$vm_ip" "sudo ls -la /etc/cni/net.d/" 2>/dev/null || echo "Failed to check CNI config"
                
                echo ""
                echo "=== Kubernetes Directory ==="
                ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no vmware-system-user@"$vm_ip" "sudo ls -la /etc/kubernetes/manifests/ 2>/dev/null || echo 'No manifests (worker node)'" 2>/dev/null
                
                # If control plane, check cluster status
                if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no vmware-system-user@"$vm_ip" "sudo test -f /etc/kubernetes/admin.conf" 2>/dev/null; then
                    echo ""
                    echo "=== Control Plane - Cluster Status ==="
                    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no vmware-system-user@"$vm_ip" "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes" 2>/dev/null || echo "Failed to get nodes"
                    
                    echo ""
                    echo "=== Control Plane - Antrea Pods ==="
                    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no vmware-system-user@"$vm_ip" "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n vmware-system-antrea" 2>/dev/null || echo "Failed to get Antrea pods"
                fi
                
                echo ""
            else
                print_warning "SSH connection failed (key doesn't match or VM not accessible)"
                echo "Manual access required (see below)"
            fi
        fi
        
        echo ""
        echo "Manual Access Methods:"
        echo "Method 1 - SSH (requires private key):"
        echo "  ssh vmware-system-user@$vm_ip"
        echo ""
        echo "Method 2 - Via vSphere Console:"
        echo "  1. Log into vCenter"
        echo "  2. Search for VM: $vm"
        echo "  3. Right-click → Launch Web Console"
        echo "  4. Login with credentials shown above"
        echo "  5. To paste password in web console:"
        echo "     - Look for 'Send Text' or 'Keyboard' icon in toolbar"
        echo "     - Or try right-click → Paste"
        echo "     - Or use 'Launch Remote Console' (desktop app) for easier paste"
        echo ""
        echo "Once connected, become root and run diagnostics:"
        echo "  sudo su -"
        echo ""
        echo "  # Check cloud-init status"
        echo "  cloud-init status"
        echo "  tail -50 /var/log/cloud-init.log"
        echo "  tail -50 /var/log/cloud-init-output.log"
        echo ""
        echo "  # Check kubelet"
        echo "  systemctl status kubelet"
        echo "  journalctl -u kubelet -n 100 --no-pager"
        echo ""
        echo "  # Check containerd"
        echo "  systemctl status containerd"
        echo ""
        echo "  # Check network connectivity to API server"
        echo "  curl -k https://$CONTROL_PLANE_IP:$CONTROL_PLANE_PORT"
        echo "  ping -c 3 $CONTROL_PLANE_IP"
        echo ""
        echo "  # Check DNS"
        echo "  cat /etc/resolv.conf"
        echo "  nslookup kubernetes.default.svc.cluster.local 2>/dev/null || echo 'DNS not working'"
        echo ""
        echo "  # Check if kubeadm ran"
        echo "  ls -la /etc/kubernetes/"
        echo "  grep -i kubeadm /var/log/syslog | tail -50"
        echo ""
        echo "  # Check CNI configuration"
        echo "  ls -la /etc/cni/net.d/"
        echo "  ls -la /opt/cni/bin/"
        echo ""
        echo "  # If this is the control plane (has /etc/kubernetes/admin.conf):"
        echo "  export KUBECONFIG=/etc/kubernetes/admin.conf"
        echo "  kubectl get nodes"
        echo "  kubectl get pods -A"
        echo "  kubectl get pods -n vmware-system-antrea  # Should have Antrea pods"
        echo ""
    fi
done

# 10. Check Supervisor Control Plane Resources (if accessible)
print_header "10. Supervisor Control Plane Resource Check"
echo ""
print_info "Checking if this is a supervisor resource issue..."
echo ""

# Try to detect if we're in a VKS environment
SUPERVISOR_NAMESPACE=$(kubectl get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.namespace}' 2>/dev/null)

if [ -n "$SUPERVISOR_NAMESPACE" ]; then
    print_info "Checking for tanzu-addons-manager issues in supervisor..."
    
    # Look for tanzu-addons-manager pods in supervisor namespace
    ADDON_MANAGER_PODS=$(kubectl get pods -A 2>/dev/null | grep -E "svc-tkg.*tanzu-addons-manager" | head -5)
    
    if [ -n "$ADDON_MANAGER_PODS" ]; then
        echo "Found tanzu-addons-manager pods:"
        echo "$ADDON_MANAGER_PODS"
        echo ""
        
        # Check if any are not Running
        if echo "$ADDON_MANAGER_PODS" | grep -qv "Running"; then
            print_error "Some tanzu-addons-manager pods are not Running!"
            echo ""
            echo "This indicates supervisor control plane resource issues."
            echo "Check supervisor resources with:"
            echo "  kubectl get pods -n svc-tkg-domain-c<X> | grep tanzu-addons-manager"
            echo "  kubectl describe pod -n svc-tkg-domain-c<X> <pod-name>"
            echo "  kubectl top nodes  # Check supervisor node resources"
            echo ""
            print_warning "SOLUTION: Increase supervisor control plane size to Medium or enable HA"
            echo ""
        else
            print_success "tanzu-addons-manager pods are running"
        fi
    else
        print_info "Could not find tanzu-addons-manager pods (may need supervisor cluster access)"
        echo ""
        echo "To check supervisor manually:"
        echo "  1. Access supervisor cluster"
        echo "  2. kubectl get pkgi -A"
        echo "  3. kubectl get pods -n svc-tkg-domain-c<X> | grep tanzu-addons-manager"
        echo "  4. kubectl top nodes  # Check CPU/memory usage"
        echo ""
        echo "If tanzu-addons-manager pods are failing due to CPU:"
        echo "  - Increase supervisor control plane size to Medium"
        echo "  - Or enable HA for the supervisor"
        echo ""
    fi
    
    # Check for packageinstall issues
    echo "Checking PackageInstall resources..."
    PKGI_ISSUES=$(kubectl get pkgi -A 2>/dev/null | grep -v "Reconcile succeeded" | tail -n +2)
    
    if [ -n "$PKGI_ISSUES" ]; then
        print_warning "Found PackageInstall issues:"
        echo "$PKGI_ISSUES"
        echo ""
        echo "This may indicate problems with addon deployment."
        echo "Check with: kubectl get pkgi -A"
        echo ""
    else
        print_info "No obvious PackageInstall issues found"
    fi
else
    print_warning "Could not determine supervisor namespace"
    echo "If workload cluster system components (Antrea, CSI) are missing,"
    echo "check supervisor control plane resources manually:"
    echo ""
    echo "  1. Access the supervisor cluster"
    echo "  2. kubectl get pkgi -A"
    echo "  3. kubectl get pods -n svc-tkg-domain-c<X>"
    echo "  4. kubectl top nodes"
    echo "  5. Look for tanzu-addons-manager pods with CPU/memory issues"
    echo ""
fi

echo ""

# 11. Diagnostic Summary and Recommendations
print_header "11. Diagnostic Summary"
echo ""
print_info "Common VM Bootstrap Issues:"
echo ""
echo "1. Network Connectivity:"
echo "   - VMs cannot reach control plane endpoint ($CONTROL_PLANE_IP:$CONTROL_PLANE_PORT)"
echo "   - DNS resolution not working inside VMs"
echo "   - Firewall blocking required ports"
echo ""
echo "2. Cloud-init Failures:"
echo "   - Cloud-init script has syntax errors"
echo "   - Required packages not available in repos"
echo "   - Bootstrap token expired before VM joined"
echo ""
echo "3. Image Issues:"
echo "   - Photon OS image missing required components"
echo "   - Cloud-init not properly configured in image"
echo "   - VM tools not running properly"
echo ""
echo "4. Certificate/Authentication:"
echo "   - Bootstrap tokens expired (tokens last 24 hours by default)"
echo "   - Certificate rotation issues"
echo "   - Time sync issues between VMs and management cluster"
echo ""
print_info "Next Steps:"
echo "  1. Access VMs via console/SSH using commands above"
echo "  2. Check cloud-init and kubelet logs on the VMs"
echo "  3. Verify network connectivity from VM to control plane"
echo "  4. Check if cluster has been up for >24 hours (token expiry)"
echo ""
print_warning "If cluster has been stuck for >24 hours, bootstrap tokens may have expired."
print_info "Consider deleting and recreating the cluster: vcf cluster delete $CLUSTER_NAME"
echo ""

print_header "Debug Report Complete"

