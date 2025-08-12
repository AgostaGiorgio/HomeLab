# Tailscale VPN Configuration Guide

## Overview

Tailscale creates a secure mesh network that allows remote access to your applications without exposing your entire home network. Perfect for accessing k3s services from mobile devices and remote locations.

## Architecture

```
Mac Mini (local) ─── 192.168.1.30:port ─── Server ─── k3s Services
                                             │
Mobile/Remote ────── 100.x.x.x:port ────────┘
(via Tailscale)
```

## Step 1: Install Tailscale on Server

Add Tailscale repository:
```bash
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu jammy main" | sudo tee /etc/apt/sources.list.d/tailscale.list
```

Install Tailscale:
```bash
sudo apt update
sudo apt install tailscale
```

Alternative installation methods:
```bash
# Universal install script
curl -fsSL https://tailscale.com/install.sh | sh

# Or using snap
sudo snap install tailscale
```

## Step 2: Connect Server to Tailscale

Start Tailscale and authenticate:
```bash
sudo tailscale up --advertise-routes=192.168.1.0/24
```

In this way all the devices in the VPN can access to the server and this is good since we are gonna put a DNS role as follows (Cloudflare example):
```
DNS ROLE
- Type: A
- Name: *
- Target: "the static IP of the server in the local network 192.168.1.30"
**DNS ONLY so in case of Cloudflare, disable the Proxy***ß
```


This `tailscale up..` command outputs a URL like `https://login.tailscale.com/a/...`
 
1. Open the URL in a browser
2. Create free Tailscale account or sign in
3. Give your server a name (e.g., "homelab-server")
4. Authorize the device

## Step 3: Verify Tailscale Connection

Check your server's Tailscale IP:
```bash
tailscale ip -4
# Shows IP like: 100.107.40.93

tailscale status
# Shows connected devices and status
```

## Step 4: Install Tailscale on Client Devices

### Mac Mini (Optional for Remote Access)
```bash
# Download from https://tailscale.com/download/mac
# Or use Homebrew:
brew install tailscale
sudo tailscale up
```

### Mobile Devices
1. **iOS**: Download "Tailscale" from App Store
2. **Android**: Download "Tailscale" from Play Store
3. Sign in with the same Tailscale account
4. Connect to your Tailscale network

### Other Computers
1. Install Tailscale client for your OS
2. Run authentication process
3. Connect to network

## Step 5: Access Patterns

### Local Network Access (Mac Mini)
- SSH: `ssh homelab` (192.168.1.30)
- Services: `http://192.168.1.30:port`
- Fast, direct connection

### Remote Access (Tailscale)
- SSH: `ssh username@100.x.x.x`
- Services: `http://100.x.x.x:port`
- Secure, encrypted tunnel

## Step 6: Optional Advanced Features

### Magic DNS
Enable in Tailscale admin console for easier access:
- Instead of: `http://100.x.x.x:8080`
- Use: `http://homelab-server:8080`

### Tailscale Serve (HTTPS)
Expose services with automatic HTTPS:
```bash
# Expose a service with HTTPS
tailscale serve https / http://localhost:8080
# Accessible at: https://homelab-server.tailnet-name.ts.net
```

### Access Control Lists (ACLs)
Configure in admin console to control device access.

## Step 7: Update SSH Config for Tailscale

Add Tailscale access to SSH config on Mac Mini:
```bash
nano ~/.ssh/config
```

Add:
```bash
Host homelab-remote
    HostName 100.x.x.x  # Your server's Tailscale IP
    User your_username
    IdentityFile ~/.ssh/id_ed25519
```

## Management

### Check Tailscale Status
```bash
tailscale status
tailscale ip -4
```

### Admin Console
- Web interface: [login.tailscale.com](https://login.tailscale.com)
- Manage devices, routes, and settings

### Restart Tailscale
```bash
sudo systemctl restart tailscale
```

## Security Benefits

✅ **Zero Trust**: All connections authenticated and encrypted  
✅ **Minimal Exposure**: Only server accessible, not entire network  
✅ **Automatic Encryption**: WireGuard protocol  
✅ **Device Management**: Centralized control  

## Troubleshooting

### Service not accessible via Tailscale:
1. Check Tailscale status: `tailscale status`
2. Verify service is running: `kubectl get svc`
3. Test local access first: `curl http://localhost:port`
4. Check firewall rules if any

### Can't connect to Tailscale:
1. Check internet connection
2. Verify account authentication
3. Restart Tailscale: `sudo systemctl restart tailscale`

### Mobile app issues:
1. Ensure using same Tailscale account
2. Check VPN is connected in app
3. Try toggling connection off/on