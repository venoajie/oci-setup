```markdown
# OCI Infrastructure Setup and Management Guide

A complete guide for setting up resilient Oracle Cloud Infrastructure (OCI) instances with persistent data storage and stable networking.

## Overview

This repository contains tools and procedures to:
1. **Prevent data loss** when instances fail (using block volumes)
2. **Maintain stable public IPs** (converting ephemeral to reserved IPs)
3. **Automate recovery** from common OCI issues

## Repository Structure
oci-setup/
├── README.md                    # This file
├── Makefile                     # Block volume setup & application deployment
├── oci-ip-convert.mk           # Ephemeral to Reserved IP conversion
├── disaster-recovery/          # Recovery scripts and procedures
│   ├── instance-recovery.sh
│   └── backup-restore.sh
└── examples/                   # Example configurations
    ├── docker-compose.yml
    └── fstab.example

## Why This Setup?

### Common OCI Problems This Solves:

1. **"Connection reset by peer" errors** after weeks/months of uptime
2. **Lost data** when instances need to be recreated
3. **Changing public IPs** that break integrations
4. **Full boot volumes** causing instance failures

### Our Solutions:

| Problem | Solution | Tool |
|---------|----------|------|
| Data loss on instance failure | Separate block volume for data | `Makefile` |
| Changing IPs on restart | Reserved (persistent) IPs | `oci-ip-convert.mk` |
| Boot volume fills up | Docker/logs on block volume | `Makefile` |
| Manual recovery is slow | Automated procedures | Both Makefiles |

## Architecture

```
OCI Instance Setup
├── Networking
│   └── Reserved Public IP (Persistent)
│       └── No more IP changes!
├── Boot Volume (30GB)
│   └── OS only - can be recreated anytime
└── Block Volume (50-200GB)
    ├── /data/docker     - Docker data
    ├── /data/apps       - Applications
    ├── /data/backups    - Local backups
    └── /data/logs       - Persistent logs
```

## Quick Start

### 1. Initial Instance Setup

```bash
# Clone this repository
git clone https://github.com/your-org/oci-setup.git
cd oci-setup

# Setup block volume for data persistence
make -f Makefile all

# Convert ephemeral IP to reserved (permanent) IP
make -f oci-ip-convert.mk convert-ip-interactive
```

### 2. Deploy Your Application

```bash
# Move Docker to block volume
make -f Makefile docker-setup

# Deploy your application (example: trading system)
make -f Makefile trading-deploy
```

## Detailed Guides

### Part 1: Block Volume Setup (Data Persistence)

This ensures your data survives instance failures.

#### Prerequisites
- OCI instance running (Oracle Linux 9 or Ubuntu 22.04/24.04)
- Block volume attached via OCI Console (50GB minimum)
- SSH access to instance

#### Setup Commands

```bash
# Check system and find block device
make check

# One-command complete setup (recommended)
make all

# OR step-by-step:
make setup      # Create partition
make format     # Format volume (WARNING: destroys data!)
make mount      # Mount volume
make permanent  # Add to /etc/fstab
make test       # Verify setup
```

#### What Gets Created
- `/data` mount point for your block volume
- Automatic mounting on reboot via `/etc/fstab`
- Proper permissions for your user

### Part 2: Reserved IP Setup (Network Stability)

Convert ephemeral (temporary) IPs to reserved (permanent) IPs.

#### Why Reserved IPs?
- **Survive instance stops/restarts**
- **Enable IP whitelisting** in external services
- **Support DNS records** that won't break
- **Required for production** workloads

#### Check Current IP Status

```bash
# See all your IPs and their types
make -f oci-ip-convert.mk audit-all-ips

# Check for instances with ephemeral IPs
make -f oci-ip-convert.mk show-ephemeral-ips

# Verify no extra charges from unused IPs
make -f oci-ip-convert.mk verify-ip-count
```

#### Convert Ephemeral to Reserved IP

```bash
# Convert a specific instance (interactive)
make -f oci-ip-convert.mk INSTANCE_NAME=your-instance-name convert-ip-interactive

# Convert all instances to reserved IPs
make -f oci-ip-convert.mk convert-all-to-reserved
```

**⚠️ WARNING**: You will get a NEW IP address. The old IP cannot be kept!

#### Example Conversion Output
```
Current Ephemeral IP: 130.61.152.252 (will be deleted)
Step 1: Deleting ephemeral IP... ✓
Step 2: Creating reserved IP... ✓
Step 3: Assigning reserved IP... ✓
CONVERSION COMPLETE!
New Reserved IP: 138.2.183.131
```

### Part 3: Docker and Application Setup

Move Docker to block volume to prevent boot volume issues.

```bash
# Stop Docker
sudo systemctl stop docker

# Move Docker data (automated)
make -f Makefile docker-setup

# Or manually:
sudo mkdir -p /data/docker
sudo mv /var/lib/docker/* /data/docker/
sudo tee /etc/docker/daemon.json << EOF
{
  "data-root": "/data/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# Restart Docker
sudo systemctl start docker
docker info | grep "Docker Root Dir"
```

## Maintenance and Operations

### Daily Checks

```bash
# Check disk usage
make -f Makefile status

# Check IP configuration
make -f oci-ip-convert.mk verify-ip-count

# Docker cleanup
docker system prune -a -f
```

### Backup Procedures

```bash
# Manual backup
make -f Makefile backup

# Schedule automatic backups
crontab -e
# Add: 0 2 * * * cd /path/to/oci-setup && make -f Makefile backup
```

## Disaster Recovery

### Scenario 1: SSH Connection Lost

```bash
# Use OCI Console Connection (no SSH needed)
# OCI Console → Instance → Console Connection → Create

# Once connected:
df -h                          # Check disk space
sudo journalctl --vacuum-time=7d   # Clean logs
sudo systemctl restart sshd        # Restart SSH
```

### Scenario 2: Instance Won't Boot

1. **Stop instance** (don't terminate!)
2. **Detach boot volume**
3. **Create new instance**
4. **Attach block volume** to new instance
5. **Run recovery**:
   ```bash
   make -f Makefile mount
   make -f Makefile docker-setup
   ```
6. **Update DNS** to new reserved IP

### Scenario 3: Accidental IP Release

```bash
# Create new reserved IP
make -f oci-ip-convert.mk INSTANCE_NAME=your-instance create-reserved-ip

# Assign to instance
make -f oci-ip-convert.mk assign-reserved-ip
```

## Best Practices

### 1. **Data Storage**
- ❌ Never store critical data on boot volume
- ✅ Always use block volume for persistent data
- ✅ Keep boot volume under 80% usage

### 2. **IP Management**
- ✅ Use reserved IPs for production
- ✅ Document IP addresses in your team wiki
- ✅ Update DNS records immediately after IP changes

### 3. **Regular Maintenance**
- Run `docker system prune` weekly
- Check disk usage daily: `make -f Makefile status`
- Verify IP configuration monthly: `make -f oci-ip-convert.mk audit-all-ips`
- Test backups quarterly

### 4. **Monitoring Setup**
```bash
# Install monitoring
make -f Makefile monitor

# Set up alerts for:
# - Disk usage > 80%
# - Memory usage > 90%
# - SSH service down
```

## Troubleshooting

### Block Volume Issues

```bash
# Volume not found
lsblk  # Should show unpartitioned disk

# Mount fails after reboot
sudo mount -a
dmesg | tail

# Disk full
make -f Makefile clean-docker
sudo journalctl --vacuum-time=3d
```

### IP Conversion Issues

```bash
# "Ephemeral IP cannot be moved or
