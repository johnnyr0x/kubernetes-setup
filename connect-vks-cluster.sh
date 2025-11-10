#!/bin/bash

# Script to connect to a VKS Kubernetes cluster
# 
# Usage: 
#   Initial setup:    ./connect-vks-cluster.sh
#   Connect cluster:  ./connect-vks-cluster.sh <cluster-name> [context-name]
#
# Features:
# - Automatically creates certificate file if not present
# - Auto-uses cluster name as context name when provided as argument
# - Labels all namespaces with privileged pod security enforcement
# - Handles authentication with API token passed via --api-token flag

set -e  # Exit on error

# VCF Automation endpoint and defaults
VCFA_ENDPOINT="vcf-automation.corp.vmbeans.com"
CERT_FILE="vcfa-cert-chain.pem"
DEFAULT_TENANT="broadcom"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
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

# Function to prompt for input with default value
prompt_input() {
    local prompt="$1"
    local default="$2"
    local result
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " result
        echo "${result:-$default}"
    else
        read -p "$prompt: " result
        echo "$result"
    fi
}

# Function to ensure certificate file exists
ensure_cert_file() {
    if [ ! -f "$CERT_FILE" ]; then
        print_info "Certificate file not found. Creating $CERT_FILE..."
        if openssl s_client -showcerts -connect "$VCFA_ENDPOINT:443" < /dev/null 2>/dev/null | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > "$CERT_FILE"; then
            print_success "Certificate file created: $CERT_FILE"
        else
            print_error "Failed to create certificate file"
            return 1
        fi
    else
        print_info "Certificate file already exists: $CERT_FILE"
    fi
}

# Function to check if any VCF contexts exist
check_vcf_contexts_exist() {
    local context_count=$(vcf context list 2>/dev/null | grep -v "^  NAME" | grep -v "^$" | grep -v "^\[" | wc -l | tr -d ' ')
    if [ "$context_count" -eq 0 ]; then
        return 1  # No contexts
    else
        return 0  # Contexts exist
    fi
}

# Function to create initial VCF context
create_initial_vcf_context() {
    print_warning "No VCF contexts found. Creating initial context..."
    echo ""
    
    # Ensure cert file exists
    ensure_cert_file
    echo ""
    
    # Get context name
    local context_name=$(prompt_input "Enter initial context name" "vcfa")
    echo ""
    
    # Prompt for API token (store in variable for reuse)
    INITIAL_API_TOKEN=$(prompt_api_token)
    echo ""
    
    print_info "Creating initial VCF context '$context_name'..."
    print_info "Endpoint: $VCFA_ENDPOINT"
    print_info "Tenant: $DEFAULT_TENANT"
    print_info "Certificate: $CERT_FILE"
    echo ""
    
    # DEBUG: Show the exact command being executed
    echo -e "${YELLOW}[DEBUG] Executing command:${NC}"
    echo "vcf context create $context_name --endpoint $VCFA_ENDPOINT --api-token <hidden> --tenant-name $DEFAULT_TENANT --ca-certificate $CERT_FILE"
    echo ""
    
    # Create initial context WITHOUT --type flag (vcf auto-detects for initial context)
    vcf context create "$context_name" \
        --endpoint "$VCFA_ENDPOINT" \
        --api-token "$INITIAL_API_TOKEN" \
        --tenant-name "$DEFAULT_TENANT" \
        --ca-certificate "$CERT_FILE"
    
    local exit_code=$?
    echo ""
    echo -e "${YELLOW}[DEBUG] Exit code: $exit_code${NC}"
    echo ""
    
    if [ $exit_code -eq 0 ]; then
        print_success "Initial VCF context 'vcfa' created successfully!"
        echo ""
        
        # Check if namespace contexts were created (e.g., vcfa:dev-wrcc9:default-project)
        print_info "Checking for namespace contexts..."
        local namespace_contexts=$(vcf context list 2>/dev/null | grep "vcfa:" | awk '{print $1}')
        
        if [ -n "$namespace_contexts" ]; then
            print_success "Found namespace contexts:"
            echo "$namespace_contexts" | while read ctx; do
                echo "  - $ctx"
            done
            echo ""
            
            # Auto-select the first namespace context
            local first_namespace_ctx=$(echo "$namespace_contexts" | head -1)
            print_info "Activating namespace context: $first_namespace_ctx"
            echo ""
            
            # Activate the namespace context (this will install plugins)
            # Provide the API token in case it's needed
            printf "%s\n%s\n" "$first_namespace_ctx" "$INITIAL_API_TOKEN" | vcf context use 2>&1 || true
            echo ""
            
            print_success "Initial VCF setup complete!"
            print_info "VCF cluster plugins have been installed and are ready to use."
        else
            print_warning "No namespace contexts found. You may need to activate a context manually."
        fi
        
        echo ""
        return 0
    else
        print_error "Failed to create initial VCF context"
        print_info "Please verify:"
        echo "  1. API token is valid and not expired"
        echo "  2. Tenant/organization name is correct"
        echo "  3. Endpoint is reachable: $VCFA_ENDPOINT"
        echo ""
        print_info "Try running this command manually:"
        echo "  vcf context create vcfa --endpoint $VCFA_ENDPOINT --api-token $api_token --tenant-name $tenant_name --ca-certificate $CERT_FILE"
        return 1
    fi
}

# Function to select context
select_vcf_context() {
    print_info "Selecting VCF context..."
    
    # Check if any contexts exist
    if ! check_vcf_contexts_exist; then
        print_warning "No VCF contexts found"
        read -p "Would you like to create the initial VCF context now? (Y/n): " create_ctx
        if [[ "$create_ctx" =~ ^[Nn]$ ]]; then
            print_error "Cannot proceed without a VCF context"
            exit 1
        fi
        create_initial_vcf_context
    else
        vcf context use
    fi
}

# Function to list clusters with auth retry
list_clusters() {
    print_info "Listing available clusters..."
    
    if ! vcf cluster list 2>&1; then
        print_warning "Failed to list clusters. Your session may have expired."
        print_info "Please re-authenticate to continue."
        
        # Get current context name
        local current_context=$(vcf context current 2>/dev/null | tail -1 || echo "")
        
        if [ -n "$current_context" ]; then
            print_info "Current context: $current_context"
            local api_token=$(prompt_api_token)
            
            # Try to refresh the current context with new credentials
            print_info "Refreshing authentication..."
            echo "$current_context" | vcf context refresh 2>&1 || true
            
            # Try listing again
            print_info "Retrying cluster list..."
            if ! vcf cluster list; then
                print_error "Still unable to list clusters. Please check your credentials and try again."
                exit 1
            fi
        else
            print_error "Could not determine current context. Please run 'vcf context use' manually first."
            exit 1
        fi
    fi
}

# Function to check cluster status
check_cluster_status() {
    local cluster_name="$1"
    local status=$(vcf cluster list | grep "^  $cluster_name " | awk '{print $3}')
    echo "$status"
}

# Function to wait for cluster to be ready
wait_for_cluster() {
    local cluster_name="$1"
    local status=$(check_cluster_status "$cluster_name")
    
    if [ "$status" != "running" ]; then
        print_warning "Cluster '$cluster_name' is currently in '$status' state (not 'running')"
        read -p "Do you want to wait for the cluster to be ready? (y/N): " wait_response
        
        if [[ "$wait_response" =~ ^[Yy]$ ]]; then
            print_info "Waiting for cluster to be ready..."
            while [ "$status" != "running" ]; do
                sleep 10
                status=$(check_cluster_status "$cluster_name")
                print_info "Current status: $status"
            done
            print_success "Cluster is now running!"
        else
            print_error "Cannot proceed with a cluster that is not running. Exiting."
            exit 1
        fi
    else
        print_success "Cluster is running and ready"
    fi
}

# Function to register JWT authenticator
register_jwt_authenticator() {
    local cluster_name="$1"
    print_info "Registering JWT authenticator for cluster: $cluster_name"
    vcf cluster register-vcfa-jwt-authenticator "$cluster_name"
    print_success "JWT authenticator registered"
}

# Function to get kubeconfig
get_kubeconfig() {
    local cluster_name="$1"
    local kubeconfig_path="${2:-$HOME/.kube/config}"
    
    print_info "Getting kubeconfig for cluster: $cluster_name"
    vcf cluster kubeconfig get "$cluster_name" --export-file "$kubeconfig_path"
    print_success "Kubeconfig exported to: $kubeconfig_path"
}

# Function to extract kubeconfig context name
get_kubecontext_name() {
    local cluster_name="$1"
    local kubeconfig_path="${2:-$HOME/.kube/config}"
    
    # Extract the context name from kubeconfig - look for contexts with the cluster name
    local context_name=$(KUBECONFIG="$kubeconfig_path" kubectl config get-contexts -o name 2>/dev/null | grep "$cluster_name" | head -1)
    
    # If that didn't work, try parsing the file directly
    if [ -z "$context_name" ]; then
        context_name=$(grep -E "^- name:.*$cluster_name" "$kubeconfig_path" | head -1 | sed 's/^- name: //' | tr -d ' ')
    fi
    
    echo "$context_name"
}

# Function to prompt for API token
prompt_api_token() {
    local api_token
    # Print to stderr so it doesn't get captured in command substitution
    print_info "API token required for context creation" >&2
    read -p "Enter API Token: " api_token
    echo "$api_token"
}

# Function to get current context endpoint and tenant info
get_current_context_info() {
    # Get current context name
    local current_ctx=$(vcf context current 2>/dev/null | tail -1 | tr -d ' ')
    
    # Get endpoint and tenant from context list
    local endpoint=$(vcf context list 2>/dev/null | grep "^  $current_ctx " | awk '{print $NF}')
    local tenant="$DEFAULT_TENANT"
    
    # If we couldn't get it from list, try the JSON method
    if [ -z "$endpoint" ]; then
        endpoint=$(vcf context current --json 2>/dev/null | grep -o '"endpoint":"[^"]*"' | cut -d'"' -f4)
        tenant=$(vcf context current --json 2>/dev/null | grep -o '"tenant":"[^"]*"' | cut -d'"' -f4)
    fi
    
    # Fallback to defaults
    if [ -z "$endpoint" ]; then
        endpoint="$VCFA_ENDPOINT"
    fi
    if [ -z "$tenant" ]; then
        tenant="$DEFAULT_TENANT"
    fi
    
    echo "$endpoint|$tenant"
}

# Function to create VCF context for a cluster
create_vcf_context() {
    local context_name="$1"
    local kubeconfig_path="${2:-$HOME/.kube/config}"
    local kubecontext="$3"
    local api_token="$4"
    
    print_info "Creating VCF context: $context_name"
    print_info "Using kubeconfig: $kubeconfig_path"
    print_info "Using kubecontext: $kubecontext"
    
    # For cluster contexts with kubeconfig, we ONLY use kubeconfig/kubecontext flags
    # No endpoint, tenant, or CA cert flags when using kubeconfig
    # Pipe the API token twice to handle multiple prompts
    printf "%s\n%s\n" "$api_token" "$api_token" | vcf context create "$context_name" \
        --type cloud-consumption-interface \
        --api-token "$api_token" \
        --kubeconfig "$kubeconfig_path" \
        --kubecontext "$kubecontext"
    
    print_success "VCF context created: $context_name"
}

# Function to refresh context with retry on auth failure
refresh_context() {
    local context_name="$1"
    local max_retries=2
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        print_info "Refreshing context: $context_name"
        
        if echo "$context_name" | vcf context refresh 2>&1; then
            print_success "Context refreshed"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "Context refresh failed. Your session may have expired."
                local api_token=$(prompt_api_token)
                print_info "Re-authenticating..."
                # Try to recreate or refresh with new token
                continue
            else
                print_error "Failed to refresh context after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Function to use/activate context with retry on auth failure
use_context() {
    local context_name="$1"
    local api_token="$2"
    local max_retries=2
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        print_info "Activating context: $context_name"
        
        # Provide token multiple times for plugin sync and other prompts
        if printf "%s\n%s\n%s\n%s\n" "$context_name" "$api_token" "$api_token" "$api_token" | vcf context use 2>&1; then
            print_success "Context activated: $context_name"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "Context activation failed. Your session may have expired."
                local new_api_token=$(prompt_api_token)
                api_token="$new_api_token"
                print_info "Re-authenticating..."
                # Try to use context again
                continue
            else
                print_error "Failed to activate context after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Function to verify connection
verify_connection() {
    print_info "Verifying connection to cluster..."
    # The pinniped auth should handle this automatically now
    kubectl get ns
    print_success "Successfully connected to cluster!"
}

# Function to display and confirm configuration
configure_settings() {
    print_info "Current Configuration:"
    echo "======================================"
    echo "  VCF Endpoint: $VCFA_ENDPOINT"
    echo "  CA Certificate: $CERT_FILE"
    echo "  Default Tenant: $DEFAULT_TENANT"
    echo "======================================"
    echo ""
    
    read -p "Would you like to customize these settings? (y/N): " customize
    if [[ "$customize" =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Customizing configuration..."
        print_info "Press Enter to keep current value, or type new value to change"
        echo ""
        
        # Endpoint
        local new_endpoint=$(prompt_input "VCF Endpoint" "$VCFA_ENDPOINT")
        VCFA_ENDPOINT="$new_endpoint"
        
        # Certificate file
        local new_cert=$(prompt_input "CA Certificate file" "$CERT_FILE")
        CERT_FILE="$new_cert"
        
        # Tenant name
        local new_tenant=$(prompt_input "Default Tenant/Organization" "$DEFAULT_TENANT")
        DEFAULT_TENANT="$new_tenant"
        
        echo ""
        print_success "Configuration updated!"
        print_info "Using:"
        echo "  VCF Endpoint: $VCFA_ENDPOINT"
        echo "  CA Certificate: $CERT_FILE"
        echo "  Default Tenant: $DEFAULT_TENANT"
        echo ""
    fi
}

# Main script logic
main() {
    echo ""
    print_info "VKS Cluster Connection Script"
    echo "======================================"
    echo ""
    
    # Step 0: Display and optionally customize configuration
    configure_settings
    
    # Step 1: Check if VCF contexts exist, create if needed
    if ! check_vcf_contexts_exist; then
        print_warning "No VCF contexts found. Initial setup required."
        echo ""
        create_initial_vcf_context
        
        # After initial setup, ask if user wants to continue to connect to a cluster
        echo ""
        read -p "Initial setup complete. Do you want to connect to a cluster now? (y/N): " connect_now
        if [[ ! "$connect_now" =~ ^[Yy]$ ]]; then
            print_info "Setup complete! Run the script again with a cluster name to connect:"
            print_info "  ./connect-vks-cluster.sh <cluster-name>"
            exit 0
        fi
        echo ""
    else
        # Ask if user wants to switch context
        read -p "Do you need to switch VCF context first? (y/N): " switch_context
        if [[ "$switch_context" =~ ^[Yy]$ ]]; then
            select_vcf_context
            echo ""
        fi
    fi
    
    # Step 2: Ensure certificate file exists
    ensure_cert_file
    echo ""
    
    # Step 3: Show available clusters
    list_clusters
    echo ""
    
    # Step 4: Get cluster name
    local cluster_name="${1:-}"
    if [ -z "$cluster_name" ]; then
        cluster_name=$(prompt_input "Enter cluster name")
    else
        print_info "Cluster name provided: $cluster_name"
    fi
    
    if [ -z "$cluster_name" ]; then
        print_error "Cluster name is required"
        exit 1
    fi
    
    print_info "Using cluster: $cluster_name"
    echo ""
    
    # Step 5: Get context name for VCF
    # If context name is provided as arg, use it. Otherwise default to cluster name
    local vcf_context_name="${2:-$cluster_name}"
    
    # If no args provided and cluster name matches the default, auto-use it
    if [ "$#" -lt 2 ]; then
        # Check if user wants to use cluster name as context name
        if [ "$cluster_name" = "$vcf_context_name" ]; then
            print_info "Auto-using cluster name as VCF context name: $vcf_context_name"
        else
            vcf_context_name=$(prompt_input "Enter VCF context name" "$cluster_name")
        fi
    else
        print_info "VCF context name provided: $vcf_context_name"
    fi
    
    echo ""
    
    # Step 6: Check cluster status and wait if needed
    wait_for_cluster "$cluster_name"
    echo ""
    
    # Step 7: Register JWT authenticator
    register_jwt_authenticator "$cluster_name"
    echo ""
    
    # Step 8: Get kubeconfig
    local kubeconfig_path="$HOME/.kube/config"
    get_kubeconfig "$cluster_name" "$kubeconfig_path"
    echo ""
    
    # Step 9: Extract kubecontext name from kubeconfig
    print_info "Extracting kubecontext name from kubeconfig..."
    local kubecontext_name=$(get_kubecontext_name "$cluster_name" "$kubeconfig_path")
    
    if [ -z "$kubecontext_name" ]; then
        print_warning "Could not automatically extract kubecontext name"
        kubecontext_name=$(prompt_input "Enter kubecontext name manually" "vcf-cli-$cluster_name@$cluster_name")
    fi
    
    print_info "Using kubecontext: $kubecontext_name"
    echo ""
    
    # Step 10: Get API token (reuse from initial setup if available)
    local api_token="${INITIAL_API_TOKEN}"
    if [ -z "$api_token" ]; then
        api_token=$(prompt_api_token)
        echo ""
    else
        print_info "Reusing API token from initial setup"
        echo ""
    fi
    
    # Step 11: Create VCF context
    create_vcf_context "$vcf_context_name" "$kubeconfig_path" "$kubecontext_name" "$api_token"
    echo ""
    
    # Step 12: Refresh context
    refresh_context "$vcf_context_name"
    echo ""
    
    # Step 13: Use/activate context
    use_context "$vcf_context_name" "$api_token"
    echo ""
    
    # Step 14: Verify connection
    print_info "Verifying connection to cluster..."
    
    # Export API token as env var in case vcf credential plugin can use it
    export VCF_API_TOKEN="$api_token"
    
    # Try kubectl with token piped for initial auth
    if ! printf "%s\n" "$api_token" | timeout 15 kubectl get ns 2>/dev/null; then
        print_warning "Initial connection attempt failed, trying interactive authentication..."
        print_info "Please enter your API token if prompted:"
        kubectl get ns
    fi
    
    print_success "Successfully connected to cluster!"
    echo ""
    
    # Step 15: Label all namespaces with privileged pod security
    print_info "Labeling all namespaces with privileged pod security enforcement..."
    if kubectl label --overwrite namespace --all pod-security.kubernetes.io/enforce=privileged 2>&1; then
        print_success "All namespaces labeled with privileged pod security"
    else
        print_warning "Failed to label namespaces (this is not critical)"
    fi
    echo ""
    
    print_success "All done! You are now connected to cluster: $cluster_name"
    print_info "You can now use 'kubectl' or 'k' commands to interact with the cluster"
}

# Run main function
main "$@"

