# HomeLab Infrastructure Setup Guide

A comprehensive guide to deploy a complete Kubernetes-based HomeLab using k3s, ArgoCD, and various infrastructure components.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      HomeLab Architecture                       │
├─────────────────────────────────────────────────────────────────┤
│  Mac Mini (Client)                                              │
│  ├─ kubectl (local access)                                      │
│  └─ SSH access (192.168.1.30)                                   │
│                                                                 │
│  Ubuntu Server (192.168.1.30)                                   │
│  ├─ SSH Server (key-based auth)                                 │
│  ├─ Tailscale VPN (100.x.x.x)                                   │
│  ├─ k3s Kubernetes                                              │
│  │  ├─ ArgoCD (GitOps)                                          │
│  │  ├─ Traefik (Ingress Controller)                             │
│  │  ├─ Cert-Manager (SSL Certificates)                          │
│  │  └─ Sealed Secrets (Secret Management)                       │
│  └─ Docker Runtime                                              │
│                                                                 │
│  Remote Access                                                  │
│  ├─ Mobile devices (via Tailscale)                              │
│  ├─ External computers (via Tailscale)                          │
│  └─ Domain routing (*.yourdomain.com → 192.168.1.30)            │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

Before starting, ensure you have:

- Ubuntu Server (20.04+ recommended) with static IP (192.168.1.30)
- Mac Mini or client machine for management
- Router with DHCP reservation capability
- Domain name (optional, for external access)
- Cloudflare account (optional, for DNS management)
- GitHub account for GitOps repository

## Table of Contents

1. [Initial Server Setup](#1-initial-server-setup)
2. [SSH Configuration](#2-ssh-configuration)
3. [Tailscale VPN Setup](#3-tailscale-vpn-setup)
4. [Kubernetes (k3s) Installation](#4-kubernetes-k3s-installation)
5. [ArgoCD GitOps Setup](#5-argocd-gitops-setup)
6. [Infrastructure Deployment](#6-infrastructure-deployment)
7. [Secret Management](#7-secret-management)
8. [Verification and Testing](#8-verification-and-testing)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Initial Server Setup

### Set Static IP Address

**Option A: Router DHCP Reservation (Recommended)**
1. Access your router's admin interface
2. Find DHCP reservations or static IP settings
3. Assign `192.168.1.30` to your server's MAC address

**Option B: Ubuntu Netplan Configuration**
```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

```yaml
network:
  version: 2
  ethernets:
    enp0s3:  # Replace with your interface name
      dhcp4: false
      addresses: [192.168.1.30/24]
      gateway4: 192.168.1.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
```

Apply configuration:
```bash
sudo netplan apply
```

### Update System
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install curl wget git nano htop -y
```

---

## 2. SSH Configuration

### Step 2.1: Install SSH Server
```bash
sudo apt install openssh-server -y
sudo systemctl enable ssh
sudo systemctl start ssh
```

### Step 2.2: Generate SSH Keys (on Mac Mini)
```bash
# Generate secure ED25519 key
ssh-keygen -t ed25519 -C "homelab@yourdomain.com"
# Save to default location: ~/.ssh/id_ed25519
# Set a strong passphrase when prompted
```

### Step 2.3: Copy Public Key to Server
```bash
# From Mac Mini - copy key to server
ssh-copy-id username@192.168.1.30

# Test connection
ssh username@192.168.1.30
```

### Step 2.4: Secure SSH Configuration
On the server, edit SSH config:
```bash
sudo nano /etc/ssh/sshd_config
```

Apply these security settings:
```bash
# Authentication
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
MaxAuthTries 3

# Network
Port 22
Protocol 2
```

Restart SSH:
```bash
sudo systemctl restart ssh
```

### Step 2.5: Set Up SSH Config (on Mac Mini)
```bash
nano ~/.ssh/config
```

```bash
Host homelab
    HostName 192.168.1.30
    User your_username
    IdentityFile ~/.ssh/id_ed25519
    Port 22

Host homelab-remote
    HostName 100.x.x.x  # Will be set after Tailscale setup
    User your_username
    IdentityFile ~/.ssh/id_ed25519
```

**Test**: `ssh homelab` should work without password prompts.

---

## 3. Tailscale VPN Setup

Tailscale provides secure remote access to your HomeLab without exposing services to the internet.

### Step 3.1: Install Tailscale on Server
```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

### Step 3.2: Connect to Tailscale Network
```bash
sudo tailscale up --advertise-routes=192.168.1.0/24
```

**Important**: This command outputs a URL. Open it in a browser to:
1. Create/sign into your Tailscale account
2. Name your device (e.g., "homelab-server")
3. Authorize the connection

### Step 3.3: Note Your Tailscale IP
```bash
tailscale ip -4
# Example output: 100.107.40.93
```

Update your SSH config on Mac Mini with this IP:
```bash
nano ~/.ssh/config
# Update the homelab-remote HostName with your Tailscale IP
```

### Step 3.4: Set Up DNS Wildcard (Optional)
If you have a domain, set up a wildcard DNS record:

**Cloudflare Example:**
- Type: `A`
- Name: `*` (wildcard)
- Target: `192.168.1.30` (your server's local IP)
- **Important**: Disable proxy/orange cloud (DNS only)

This allows `*.yourdomain.com` to resolve to your server when on your local network.

---

## 4. Kubernetes (k3s) Installation

### Step 4.1: Install k3s
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik --write-kubeconfig-mode 644" sh -
```

**Why disable Traefik?** We'll install it via ArgoCD with custom configuration.

### Step 4.2: Configure kubectl Access
```bash
# Make kubeconfig accessible
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# Copy to user directory
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config
```

### Step 4.3: Enable External Access
Get your Tailscale IP and configure k3s for external connections:
```bash
TAILSCALE_IP=$(tailscale ip -4)
echo "Configuring k3s for external access. Tailscale IP: $TAILSCALE_IP"

sudo systemctl edit k3s
```

Add this configuration:
```ini
[Service]
ExecStart=
ExecStart=/usr/local/bin/k3s server --bind-address=0.0.0.0 --tls-san=192.168.1.30 --tls-san=$TAILSCALE_IP --write-kubeconfig-mode=644 --disable=traefik
```

Apply changes:
```bash
sudo systemctl daemon-reload
sudo systemctl restart k3s
```

### Step 4.4: Fix kubeconfig Server Address
```bash
# Fix server address for local access
sudo sed -i 's/server: https:\/\/0.0.0.0:6443/server: https:\/\/127.0.0.1:6443/' /etc/rancher/k3s/k3s.yaml
sed -i 's/server: https:\/\/0.0.0.0:6443/server: https:\/\/127.0.0.1:6443/' ~/.kube/config
```

### Step 4.5: Set Up kubectl on Mac Mini
```bash
# Copy kubeconfig from server
scp homelab:/etc/rancher/k3s/k3s.yaml ~/.kube/homelab-config

# Fix server address for remote access
sed -i '' 's/127.0.0.1/192.168.1.30/' ~/.kube/homelab-config

# Test connection
KUBECONFIG=~/.kube/homelab-config kubectl get nodes
```

Make it permanent:
```bash
echo 'export KUBECONFIG=~/.kube/homelab-config' >> ~/.zshrc
source ~/.zshrc

# Test
kubectl get nodes
```

**Expected Output:**
```
NAME        STATUS   ROLES                       AGE   VERSION
homelab     Ready    control-plane,master        5m    v1.28.x+k3s1
```

---

## 5. ArgoCD GitOps Setup

ArgoCD provides GitOps-based deployment and management of your infrastructure.

### Step 5.1: Create ArgoCD Namespace
```bash
kubectl create namespace argocd
```

### Step 5.2: Install ArgoCD
```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Step 5.3: Expose ArgoCD UI
```bash
kubectl -n argocd patch svc argocd-server \
  -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "targetPort": 8080, "nodePort": 30080}]}}'
```

### Step 5.4: Get Default Credentials
```bash
# Username is: admin
# Get password:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode; echo
```

### Step 5.5: Access ArgoCD UI
- **Local access**: http://192.168.1.30:30080
- **Remote access**: http://100.x.x.x:30080 (via Tailscale)

**Login with:**
- Username: `admin`
- Password: (from previous step)

### Step 5.6: Configure Git Repository (Optional)
If using a private repository, add SSH key or token in ArgoCD UI:
1. Go to Settings → Repositories
2. Click "Connect Repo using SSH" or "Connect Repo using HTTPS"
3. Add your repository URL and credentials

---

## 6. Infrastructure Deployment

Deploy core infrastructure components using ArgoCD and the configurations in this repository.

### Step 6.1: Apply Infrastructure App-of-Apps
```bash
kubectl apply -f infra/infra-app.yaml
```

This deploys the main infrastructure application that manages:
- **Sealed Secrets**: Encrypted secret management
- **Cert-Manager**: Automatic SSL certificate management
- **Traefik**: Ingress controller with load balancing

### Step 6.2: Verify Deployment in ArgoCD UI
1. Open ArgoCD UI (http://192.168.1.30:30080)
2. You should see the "infra" application
3. Click on it to see the child applications:
   - `cert-manager`
   - `sealed-secrets`
   - `traefik`

### Step 6.3: Monitor Application Sync Status
All applications should show:
- **Status**: `Synced` and `Healthy`
- **Last Sync**: Recent timestamp

If any application shows `OutOfSync`, click on it and press "Sync" button.

---

## 7. Secret Management

This section handles encrypted secrets using Sealed Secrets for secure GitOps.

### Step 7.1: Install kubeseal CLI (on Server)
```bash
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.26.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### Step 7.2: Handle Existing Installation

**If this is a fresh installation:**
1. Wait for sealed-secrets controller to be ready
2. Back up the encryption keys for future use:

```bash
# Backup sealed-secrets keys
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-master.key

# Store this file securely (e.g., in Bitwarden, 1Password, etc.)
```

**If restoring from existing backup:**
1. Some applications may fail initially due to missing secrets
2. Apply your backed-up encryption keys:

```bash
# Apply previously backed up keys
kubectl apply -f sealed-secrets-master.key
```

3. Restart the sealed-secrets controller:

```bash
kubectl delete pod -n kube-system -l name=sealed-secrets-controller
```

4. Force sync all applications in ArgoCD

### Step 7.3: Create Encrypted Secrets
Example of creating a sealed secret for Cloudflare API token:

```bash
# Create the secret (replace with your actual token)
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=your_cloudflare_token_here \
  --dry-run=client -o yaml | kubeseal -o yaml > cloudflare-token-sealed.yaml

# Apply the sealed secret
kubectl apply -f cloudflare-token-sealed.yaml
```

---

## 8. Verification and Testing

### Step 8.1: Check All Pods
```bash
kubectl get pods -A
```

All pods should show `Running` status. Key namespaces to check:
- `argocd`: ArgoCD components
- `cert-manager`: Certificate management
- `kube-system`: Core k3s and sealed-secrets
- `traefik`: Ingress controller

### Step 8.2: Test Certificate Issuance
```bash
# Check if cluster issuer is ready
kubectl get clusterissuer

# Test certificate creation
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: default
spec:
  secretName: test-cert-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - test.yourdomain.com
EOF

# Check certificate status
kubectl describe certificate test-cert
```

### Step 8.3: Test Ingress
```bash
# Apply test ingress (in test/ directory)
kubectl apply -f test/
```

### Step 8.4: Access Tests
- **Local**: http://test.yourdomain.com (should resolve to 192.168.1.30)
- **Remote**: http://test.yourdomain.com (via Tailscale routing)

---

## 9. Troubleshooting

### Common Issues and Solutions

#### ArgoCD Applications Stuck in "Progressing"
```bash
# Check application logs
kubectl logs -n argocd deployment/argocd-application-controller

# Force refresh
kubectl patch app infra -n argocd -p '{"metadata": {"annotations": {"argocd.argoproj.io/refresh": "now"}}}' --type merge
```

#### Sealed Secrets Not Working
```bash
# Check sealed-secrets controller logs
kubectl logs -n kube-system -l name=sealed-secrets-controller

# Verify keys are present
kubectl get secrets -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key

# If keys are missing, apply backup:
kubectl apply -f sealed-secrets-master.key
kubectl delete pod -n kube-system -l name=sealed-secrets-controller
```

#### Certificate Issues
```bash
# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check certificate status
kubectl describe certificate your-cert-name

# Check challenges
kubectl get challenges -A
```

#### Network Connectivity Issues
```bash
# Test local access
curl -I http://192.168.1.30:30080

# Test Tailscale connectivity
tailscale ping homelab-server

# Check k3s networking
kubectl get svc -A
kubectl get endpoints -A
```

#### DNS Resolution Issues
```bash
# Test DNS resolution
nslookup yourdomain.com
dig yourdomain.com

# Check CoreDNS
kubectl logs -n kube-system deployment/coredns
```

### Useful Commands

```bash
# Check cluster status
kubectl cluster-info

# View all resources
kubectl get all -A

# Describe node details
kubectl describe node

# Check resource usage
kubectl top nodes
kubectl top pods -A

# ArgoCD CLI commands (after installing argocd CLI)
argocd app list
argocd app sync infra
argocd app get infra
```

### Log Locations

- **k3s**: `/var/log/syslog` or `journalctl -u k3s`
- **Tailscale**: `journalctl -u tailscaled`
- **SSH**: `/var/log/auth.log`

---

## Contributing

To contribute to this HomeLab setup:

1. Fork the repository
2. Create a feature branch
3. Test changes in your environment
4. Submit a pull request

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review logs for specific components
3. Search GitHub issues in the repository
4. Create a new issue with detailed information

---

**Happy HomeLab-ing! 🏠🚀**