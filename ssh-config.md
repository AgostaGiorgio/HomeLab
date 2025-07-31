# SSH Server Setup and Key Authentication

## Prerequisites

> **Important**: It's highly recommended to assign a static IP to your server (e.g., 192.168.1.30) before proceeding. This can be done through your router's DHCP reservation settings.

## Step 1: Install SSH Server

On your Ubuntu server:

```bash
sudo apt update
sudo apt install openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
```

## Step 2: Generate SSH Key Pair

On your client machine (Mac Mini):

```bash
# Generate ED25519 key (recommended)
ssh-keygen -t ed25519 -C "your_email@example.com"

# When prompted:
# - File location: Press Enter for default (~/.ssh/id_ed25519)
# - Passphrase: Choose a strong passphrase (recommended) or leave empty
```

This creates two files:
- `~/.ssh/id_ed25519` (private key - keep secret!)
- `~/.ssh/id_ed25519.pub` (public key - goes on server)

## Step 3: Copy Public Key to Server

### Method A: Using ssh-copy-id (easiest)
```bash
# From your Mac Mini
ssh-copy-id username@192.168.1.30
```

### Method B: Manual copy
```bash
# From your Mac Mini - display your public key
cat ~/.ssh/id_ed25519.pub
# Copy the output

# On your Ubuntu server
mkdir -p ~/.ssh
nano ~/.ssh/authorized_keys
# Paste your public key here, save and exit

# Set correct permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

## Step 4: Test Key Authentication

From your Mac Mini:
```bash
ssh username@192.168.1.30
```

You should connect using your key (prompted for passphrase if you set one).

## Step 5: Secure SSH Configuration

On your Ubuntu server:
```bash
sudo nano /etc/ssh/sshd_config
```

Make these changes:
```bash
# Disable password authentication
PasswordAuthentication no
ChallengeResponseAuthentication no

# Ensure key authentication is enabled
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Security settings
PermitRootLogin no
Port 22
Protocol 2
PermitEmptyPasswords no

# Optional: Limit login attempts
MaxAuthTries 3
MaxStartups 2

# Optional: Allow only specific users
AllowUsers your_username
```

Restart SSH service:
```bash
sudo systemctl restart ssh
```

## Step 6: Test Secure Configuration

**Important**: Don't close your current SSH session! Open a new terminal and test:
```bash
ssh username@192.168.1.30
```

Should work with key authentication only.

## Step 7: Optional - SSH Config for Convenience

On your Mac Mini, create SSH config:
```bash
nano ~/.ssh/config
```

Add:
```bash
Host homelab
    HostName 192.168.1.30
    User your_username
    IdentityFile ~/.ssh/id_ed25519
    Port 22
```

Now connect simply with:
```bash
ssh homelab
```

## Step 8: Optional - SSH Agent Setup

For passphrase management on Mac Mini:
```bash
# Add key to SSH agent
ssh-add ~/.ssh/id_ed25519

# Make it persistent (add to ~/.zshrc or ~/.bash_profile)
ssh-add --apple-use-keychain ~/.ssh/id_ed25519 2>/dev/null
```

## Troubleshooting

### Key authentication not working:
1. Check SSH logs: `sudo tail -f /var/log/auth.log`
2. Check permissions: `ls -la ~/.ssh/`
3. Test with verbose: `ssh -v username@192.168.1.30`
4. Verify key format: `ssh-keygen -l -f ~/.ssh/authorized_keys`

### File permissions should be:
- `~/.ssh/` directory: `drwx------ (700)`
- `~/.ssh/authorized_keys`: `-rw------- (600)`

## Security Best Practices

- ✅ Use strong passphrases for private keys
- ✅ Never share private keys
- ✅ Keep backups of private keys securely
- ✅ Consider changing SSH port from 22
- ✅ Enable fail2ban for additional protection
- ✅ Regularly audit SSH access logs