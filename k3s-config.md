# k3s Kubernetes Setup and Configuration

## Overview

k3s is a lightweight Kubernetes distribution perfect for home labs. This guide covers installation, configuration for both local and Tailscale access, and kubectl setup.

## Step 1: Install k3s

On your Ubuntu server:
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik --write-kubeconfig-mode 644" sh -
```

This installs:
- k3s server
- kubectl command
- Default storage provisioner
- Traefik ingress controller
- CoreDNS for service discovery

## Step 2: Fix kubectl Permissions

By default, kubectl requires sudo. Fix this:
```bash
# Make kubeconfig readable
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# Copy to user directory
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config
```

Test kubectl:
```bash
kubectl get nodes
kubectl get pods -A
```

## Step 3: Configure k3s for External Access

To access k3s from other machines and via Tailscale:

```bash
# Get your Tailscale IP
TAILSCALE_IP=$(tailscale ip -4)
echo "Tailscale IP: $TAILSCALE_IP"

# Configure k3s to accept external connections
sudo systemctl edit k3s
```

Add this configuration:
```ini
[Service]
ExecStart=
ExecStart=/usr/local/bin/k3s server --bind-address=0.0.0.0 --tls-san=192.168.1.30 --tls-san=100.x.x.x --write-kubeconfig-mode=644 --disable=traefik
```

Replace `100.x.x.x` with your actual Tailscale IP.

Apply changes:
```bash
sudo systemctl daemon-reload
sudo systemctl restart k3s
```

## Step 4: Fix kubeconfig Server Address

After restart, fix the server address in kubeconfig:
```bash
# Fix server address to use localhost
sudo sed -i 's/server: https:\/\/0.0.0.0:6443/server: https:\/\/127.0.0.1:6443/' /etc/rancher/k3s/k3s.yaml

# Update your user config
sed -i 's/server: https:\/\/0.0.0.0:6443/server: https:\/\/127.0.0.1:6443/' ~/.kube/config
```

Test kubectl:
```bash
kubectl get nodes
kubectl get pods -A
```

## Step 5: Set Up kubectl on Mac Mini

### Copy kubeconfig to Mac Mini
```bash
# From Mac Mini, copy the config
scp homelab:/etc/rancher/k3s/k3s.yaml ~/.kube/homelab-config

# Fix server address to use server's local IP
sed -i '' 's/127.0.0.1/192.168.1.30/' ~/.kube/homelab-config

# Test kubectl from Mac Mini
KUBECONFIG=~/.kube/homelab-config kubectl get nodes
```

### Make it permanent (optional)
```bash
# Add to shell profile on Mac Mini
echo 'export KUBECONFIG=~/.kube/homelab-config' >> ~/.zshrc
source ~/.zshrc

# Test
kubectl get nodes
```

## Step 6: Verify Default Components

Check that k3s installed default components:
```bash
kubectl get pods -A
```

You should see:
- **coredns**: DNS server for the cluster
- **traefik**: Ingress controller for HTTP/HTTPS routing
- **local-path-provisioner**: Persistent storage
- **metrics-server**: Resource usage metrics
- **svclb-traefik**: Service load balancer

All pods should be in "Running" or "Completed" status.