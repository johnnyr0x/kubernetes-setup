# Kubernetes Setup Scripts

This repository contains scripts to help automate VKS (VMware Kubernetes Service) cluster setup and connection.

## Scripts

### connect-vks-cluster.sh

A comprehensive shell script that automates VKS (VMware Kubernetes Service) cluster connections, including initial VCF setup, plugin installation, and cluster connectivity.

#### Prerequisites

- `vcf` CLI tool installed
- `kubectl` installed  
- `openssl` for certificate generation
- Access to VCF Automation endpoint
- Valid API token for authentication

#### Environment Variables (Optional)

These variables can be set to override default values or avoid prompts:

- `VCF_ENDPOINT`: Specifies the VCF Automation endpoint (e.g., `vcf-automation.corp.vmbeans.com`)
- `VCF_TENANT`: Specifies the default tenant/organization name (e.g., `broadcom`)

#### Features

- **Automatic initial setup** - Creates VCF context and installs plugins on first run
- **Configurable settings** - Customize endpoint, certificate, and tenant at runtime
- **Certificate auto-generation** - Automatically creates CA certificate chain if missing
- **Single API token entry** - Token is reused throughout the session (no repeated prompts)
- **Smart context naming** - Auto-uses cluster name as context name
- **Namespace labeling** - Automatically applies privileged pod security labels
- **Error recovery** - Handles expired sessions and authentication failures
- **Cluster status checking** - Waits for clusters to be ready before connecting

#### Usage

**First-time setup** (creates initial VCF context and installs plugins):
```bash
./connect-vks-cluster.sh
```

**Connect to a cluster** (after initial setup):
```bash
./connect-vks-cluster.sh vks-01
```

**With custom VCF context name**:
```bash
./connect-vks-cluster.sh vks-01 my-custom-context
```

#### Configuration

On first run or anytime, you can customize default settings:

```
[INFO] Current Configuration:
======================================
  VCF Endpoint: vcf-automation.corp.vmbeans.com
  CA Certificate: vcfa-cert-chain.pem
  Default Tenant: broadcom
======================================

Would you like to customize these settings? (y/N):
```

Press `y` to change settings, or `N` to use defaults. Press Enter on any prompt to keep the current value.

#### What it does

##### Initial Setup (First Run):
1. **Configuration review** - Shows and allows customization of endpoint, certificate, and tenant
2. **Certificate creation** - Generates CA certificate chain from VCF endpoint if missing
3. **Context name** - Prompts for initial VCF context name (default: `vcfa`)
4. **API token** - Prompts for your API token (visible for easy copy/paste)
5. **Create VCF context** - Creates the main VCF Automation context with certificate
6. **Activate namespace context** - Automatically selects the namespace-specific context
7. **Install plugins** - Installs required VCF CLI plugins (`cluster`, `vm`, `package`, etc.)
8. **Ready to connect** - Prompts whether to connect to a cluster immediately or exit

##### Cluster Connection:
1. **List clusters** - Shows available VKS clusters with status and versions
2. **Cluster selection** - Uses command-line argument or prompts for cluster name
3. **Status check** - Verifies cluster is running, offers to wait if still creating
4. **JWT authenticator** - Registers the JWT authenticator for the cluster
5. **Get kubeconfig** - Downloads and merges kubeconfig to `~/.kube/config`
6. **Extract kubecontext** - Automatically extracts the kubecontext name
7. **Create cluster context** - Creates VCF context for the specific cluster (reuses API token from setup)
8. **Refresh and activate** - Refreshes and switches to the cluster context
9. **Verify connection** - Tests connection by listing namespaces
10. **Label namespaces** - Applies `pod-security.kubernetes.io/enforce=privileged` to all namespaces

#### Example Session

```bash
$ ./connect-vks-cluster.sh vks-01

[INFO] VKS Cluster Connection Script
======================================

[INFO] Current Configuration:
======================================
  VCF Endpoint: vcf-automation.corp.vmbeans.com
  CA Certificate: vcfa-cert-chain.pem
  Default Tenant: broadcom
======================================

Would you like to customize these settings? (y/N): n
[INFO] Currently active VCF context: vcfa:dev-wrcc9:default-project
Do you need to switch VCF context first? (y/N): n
[INFO] Certificate file already exists: vcfa-cert-chain.pem

[INFO] Listing available clusters...
  NAME                     NAMESPACE  STATUS    CONTROLPLANE  WORKERS  KUBERNETES             KUBERNETESRELEASE        
  vks-01                   dev-wrcc9  running   1/1           2/2      v1.33.3+vmware.1-fips  v1.33.3---vmware.1-fips-vkr.1
  # ... other clusters ...

[INFO] Cluster name provided: vks-01
[INFO] Using cluster: vks-01
[INFO] Auto-using cluster name as VCF context name: vks-01
[SUCCESS] Cluster is running and ready
[INFO] Registering JWT authenticator for cluster: vks-01
[SUCCESS] JWT authenticator registered
[INFO] Getting kubeconfig for cluster: vks-01
[SUCCESS] Kubeconfig exported to: /home/user/.kube/config
[INFO] Extracting kubecontext name from kubeconfig...
[INFO] Using kubecontext: vcf-cli-vks-01-dev-wrcc9@vks-01-dev-wrcc9
[INFO] API token required for context creation
Enter API Token: ****************************************
[INFO] Creating VCF context: vks-01
[SUCCESS] VCF context created: vks-01
[INFO] Refreshing context: vks-01
[SUCCESS] Context refreshed
[INFO] Activating context: vks-01
[SUCCESS] Context activated: vks-01
[INFO] Verifying connection to cluster...
[SUCCESS] Successfully connected to cluster!
[INFO] Labeling all namespaces with privileged pod security enforcement...
[SUCCESS] All namespaces labeled with privileged pod security
[SUCCESS] All done! You are now connected to cluster: vks-01
[INFO] You can now use 'kubectl' or 'k' commands to interact with the cluster
[INFO] To set 'k' as an alias for 'kubectl' in your current session, run:
[INFO]   alias k=kubectl
```

#### Manual Steps (for reference)

If you prefer to run the commands manually, here are the steps:

```bash
# 1. Switch context (if needed)
vcf context use
# Select: vcfa:dev-wrcc9:default-project

# 2. List clusters
vcf cluster list

# 3. Register JWT authenticator
vcf cluster register-vcfa-jwt-authenticator vks-01

# 4. Get kubeconfig
vcf cluster kubeconfig get vks-01 --export-file ~/.kube/config

# 5. Check the kubecontext name
cat ~/.kube/config | grep vks-01

# 6. Create VCF context (you'll be prompted for API token)
vcf context create vks-01 --kubeconfig ~/.kube/config --kubecontext vcf-cli-vks-01-dev-wrcc9@vks-01-dev-wrcc9
# Enter API Token: Phps5YkbCwAHmvbfWVI5cZRkfJjc1BZk

# 7. Refresh context
vcf context refresh
# Select: vks-01

# 8. Use context
vcf context use
# Select: vks-01

# 9. Verify connection
kubectl get ns
```

---

## Debug Script

### debug-vks-vms.sh

A comprehensive debugging script for troubleshooting VKS cluster issues at the VM level. Use this when clusters are stuck in provisioning or nodes won't become Ready.

#### Prerequisites

- `kubectl` installed
- `ssh` client

#### Environment Variables (Optional)

- `K8S_NAMESPACE`: Specifies the Kubernetes namespace to search for VMs (e.g., `dev-wrcc9`)

#### Usage

```bash
./debug-vks-vms.sh <cluster-name> [namespace]
```

**Example:**
```bash
./debug-vks-vms.sh vks-04
# or with custom namespace
./debug-vks-vms.sh vks-04 my-namespace
# or using environment variable
K8S_NAMESPACE=my-namespace ./debug-vks-vms.sh vks-04
```

#### What it does

1. **VM Status** - Shows power state, VM tools status, and network info
2. **Network Details** - Displays IP addresses for all VMs
3. **Bootstrap Secrets** - Validates cloud-init configuration
4. **Machine Health** - Shows Kubernetes machine conditions
5. **Connectivity Tests** - Tests control plane endpoint access
6. **Login Credentials** - Automatically retrieves SSH passwords for VMs
7. **Access Instructions** - Provides SSH and console access commands
8. **Diagnostic Summary** - Lists common issues and solutions

#### Key Features

- **Automatic password retrieval** - Gets VM passwords from Kubernetes secrets
- **Automated SSH log collection** - If SSH key is available, automatically collects logs from VMs
- **Console paste instructions** - Shows how to paste passwords in vSphere web console
- **Control plane detection** - Identifies which VMs are control plane vs workers
- **Supervisor resource checking** - Detects CPU/memory constraints on supervisor control plane
- **Comprehensive diagnostics** - Checks VMs, machines, secrets, connectivity, and platform resources

#### Security Note on SSH Passwords

`debug-vks-vms.sh` retrieves and displays the `vmware-system-user` SSH password for your cluster's VMs. Be mindful of where you run this script and how its output is handled to avoid exposing sensitive credentials in insecure environments (e.g., public logs, shared screens).

#### Example Output

```bash
$ ./debug-vks-vms.sh vks-04

========================================
VKS VM-Level Debug Report: vks-04
========================================

Login Credentials for VMs:
  Username: vmware-system-user
  Password: LJ3dptPzU5PyfOdSaVlIBxoW3KLX/cubqqHYikBDNls=

After login, become root with: sudo su -

VM: vks-04-control-plane (IP: 192.173.237.67)
Method 1 - SSH (requires private key):
  ssh vmware-system-user@192.173.237.67

Method 2 - Via vSphere Console:
  1. Log into vCenter
  2. Search for VM: vks-04-control-plane
  3. Right-click → Launch Web Console
  4. Login with credentials shown above
  ...
```

---

#### Troubleshooting

**Issue**: Session expired / Authentication error when listing clusters
- **Error**: `unable to get cluster client while listing kubernetes clusters: the server has asked for the client to provide credentials`
- **Solution**: Your VCF session has expired (typically after 1 hour). The script will automatically detect this and prompt you to re-enter your API token to refresh authentication.

**Issue**: Cluster is not in 'running' state
- **Error**: `Cluster 'vks-02' is currently in 'creating' state (not 'running')`
- **Solution**: The script will ask if you want to wait for the cluster to be ready. Choose 'y' to wait, or 'N' to exit and try again later. It typically takes 5-15 minutes for a cluster to reach 'running' state.

**Issue**: Cluster stuck in 'running' but nodes never become Ready
- **Error**: Nodes show as "NotReady" for hours, kubelet logs show `cni plugin not initialized`
- **Root Cause**: Antrea CNI and other system components were not deployed during cluster creation
- **Common Causes**:
  1. **Supervisor Control Plane CPU exhaustion** - `tanzu-addons-manager` can't run due to insufficient resources
  2. VKS platform bug during cluster creation
- **Solution**: 
  1. Use `./debug-vks-vms.sh <cluster-name>` to confirm CNI is missing
  2. **Check Supervisor Control Plane resources**:
     ```bash
     # SSH to supervisor cluster
     kubectl get pkgi -A
     kubectl get pods -n svc-tkg-domain-c<X> | grep tanzu-addons-manager
     kubectl top nodes  # Check CPU/memory usage
     ```
  3. **If CPU exhaustion**: Increase supervisor control plane size to Medium or enable HA
  4. **If platform bug**: Delete and recreate the cluster:
     ```bash
     vcf cluster delete <cluster-name>
     vcf cluster create <cluster-name> --kubernetes-version=v1.34.1+vmware.1 --control-plane-count=1 --worker-count=1
     ./connect-vks-cluster.sh <cluster-name>
     ```
- **How to diagnose on workload cluster**: SSH to control plane and run:
  ```bash
  export KUBECONFIG=/etc/kubernetes/admin.conf
  kubectl get pods -n vmware-system-antrea  # Should have pods, not empty
  kubectl get pods -n vmware-system-csi  # Should have CSI driver
  kubectl get nodes  # Shows NotReady if CNI missing
  ls -la /etc/cni/net.d/  # Should have config files
  kubectl describe nodes | grep Taints  # Check for uninitialized taint
  ```

**Issue**: JWT authenticator registration fails
- **Error**: `unable to retrieve the complete list of server APIs`
- **Solution**: This usually means the cluster isn't fully ready yet. Wait a few more minutes and try again.

**Issue**: Script fails to extract kubecontext name
- **Solution**: The script will prompt you to enter it manually. You can find it by running:
  ```bash
  cat ~/.kube/config | grep "name: vcf-cli-"
  ```

**Issue**: Context creation fails
- **Solution**: Make sure you have the correct kubeconfig path and kubecontext name
- Verify the kubeconfig was properly exported with `cat ~/.kube/config`

**Issue**: Cannot connect to cluster after script completes
- **Solution**: Try running `vcf context refresh` and `vcf context use` manually to select your cluster context

## License

MIT

