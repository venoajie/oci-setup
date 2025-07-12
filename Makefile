I'll create two files for you: a comprehensive README.md and a well-documented Makefile.

## File 1: README.md

```markdown
# OCI Block Volume Setup and Data Persistence Guide

This guide ensures your Oracle Cloud Infrastructure (OCI) instance data survives instance failures, preventing the "Connection reset by peer" issue that forces you to recreate instances and lose data.

## Why This Setup?

After weeks or months, OCI instances can become permanently disconnected with SSH errors:
```
kex_exchange_identification: read: Connection reset by peer
Connection reset by 130.61.246.120 port 22
```

**Root causes:**
- Boot volume fills up (logs, Docker images)
- OS updates break SSH
- Instance hardware failure
- Accidental termination

**This guide prevents data loss by:**
- Separating OS from data (boot volume vs data volume)
- Automating backups
- Providing quick recovery procedures

## Architecture Overview

```
OCI Instance
├── Boot Volume (30GB) - OS only, can be recreated
│   ├── /boot
│   ├── /etc
│   └── /var (except Docker)
└── Block Volume (50-200GB) - Your persistent data
    ├── /data/docker      - Docker data directory
    ├── /data/apps        - Application data
    ├── /data/backups     - Local backups
    └── /data/logs        - Persistent logs
```

This decoupled architecture ensures that a failure or restart of one service does not cause a cascading failure of the entire system.

## 1. Prerequisites

*   Oracle Cloud account (Free Tier or PAYG)
*   Running OCI instance (Oracle Linux 9 or Ubuntu 22.04/24.04)
*   Block Volume attached via OCI Console (50GB minimum)
*   SSH access to the instance
*   Basic Linux command line knowledge

## 2. Initial Setup - Block Volume Configuration

### Step 2.1: Download and Prepare the Makefile

```bash
# Download the Makefile
wget https://raw.githubusercontent.com/your-repo/oci-setup/main/Makefile
# OR create it manually: nano Makefile (then paste content)

# Check what the Makefile detected
make check

# See all available commands
make help
```

### Step 2.2: One-Command Setup (Recommended)

For a complete automated setup:

```bash
# This will partition, format, mount, and configure the block volume
make all
```

**What happens:**
1. Creates partition on the attached block device
2. Formats it as ext4 filesystem
3. Mounts to /data
4. Adds to /etc/fstab for persistence
5. Tests read/write access

### Step 2.3: Manual Step-by-Step (If Needed)

If you prefer to run each step individually:

```bash
# 1. Check system and find block device
make check

# 2. Create partition on the device
make setup

# 3. Format the partition (WARNING: Destroys any existing data!)
make format

# 4. Mount the volume
make mount

# 5. Make mounting permanent (survives reboot)
make permanent

# 6. Test everything works
make test
```

### Step 2.4: Post-Setup Configuration

```bash
# Install monitoring scripts
make monitor

# Create backup scripts
make backup

# View current configuration
make info
```

## 3. Docker and Application Setup

### Step 3.1: Move Docker to Block Volume

```bash
# Stop Docker
sudo systemctl stop docker

# Move Docker data
sudo mkdir -p /data/docker
sudo mv /var/lib/docker/* /data/docker/

# Configure Docker to use new location
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

# Start Docker
sudo systemctl start docker
docker info | grep "Docker Root Dir"
```

### Step 3.2: Application Deployment Example

Here's an example for deploying a trading application:

```bash
# Create application directory
mkdir -p /data/apps/trading-app
cd /data/apps/trading-app

# Clone your application
git clone https://github.com/your-org/trading-app.git .

# Create secrets directory
mkdir -p secrets
chmod 700 secrets

# Create secret files (example)
echo "YOUR_CLIENT_ID" > secrets/client_id.txt
echo "YOUR_CLIENT_SECRET" > secrets/client_secret.txt
chmod 600 secrets/*.txt

# Deploy with Docker Compose
docker compose up -d
```

## 4. Daily Operations and Maintenance

### Monitoring Disk Usage

```bash
# Quick check
make status

# Detailed usage
df -h /data
du -sh /data/*

# Find large files
find /data -type f -size +100M -exec ls -lh {} \;
```

### Backup Procedures

```bash
# Manual backup
make backup

# Schedule automatic backups (add to crontab)
crontab -e
# Add: 0 2 * * * cd /home/ubuntu && make backup
```

### Docker Cleanup (Regular Maintenance)

```bash
# Remove unused Docker data
docker system prune -a -f

# Check Docker space usage
docker system df

# Clean old logs
find /data/logs -name "*.log" -mtime +30 -delete
```

## 5. Disaster Recovery Procedures

### Scenario 1: SSH Connection Lost

```bash
# 1. Try OCI Console Connection (no SSH needed)
# OCI Console → Instance → Console Connection → Create

# 2. Once connected via console:
df -h                      # Check if disk full
systemctl status sshd      # Check SSH service
journalctl -xe            # Check system logs

# 3. Common fixes:
sudo journalctl --vacuum-time=7d    # Clean logs
sudo systemctl restart sshd          # Restart SSH
```

### Scenario 2: Instance Won't Boot

```bash
# 1. Stop instance (don't terminate!)
# 2. Detach boot volume
# 3. Your data is safe on block volume!
# 4. Create new instance
# 5. Attach block volume to new instance
# 6. Run: make mount
# 7. Continue working with your data intact
```

### Scenario 3: Restore from Backup

```bash
# List available backups
ls -la /data/backups/

# Restore specific backup
cd /
sudo tar -xzf /data/backups/data-20240115-020000.tar.gz
```

## 6. Best Practices

1. **Never store critical data on boot volume**
   - Boot volume = OS only
   - Block volume = All your data

2. **Regular maintenance**
   - Run `docker system prune` weekly
   - Check disk usage daily
   - Test backups monthly

3. **Monitor proactively**
   - Set up disk usage alerts
   - Watch system logs
   - Keep 20% free space

4. **Document everything**
   - Keep this README updated
   - Document any custom configurations
   - Note any issues and solutions

## 7. Troubleshooting

### Block Volume Not Found
```bash
# Check if volume is attached in OCI Console
# Then run:
lsblk
# Look for unpartitioned disk (usually /dev/sdb)
```

### Mount Fails After Reboot
```bash
# Check /etc/fstab entry
cat /etc/fstab | grep data

# Test mount
sudo mount -a

# Check for errors
dmesg | tail
```

### Disk Full Errors
```bash
# Find what's using space
du -h /data | sort -rh | head -20

# Clean Docker
docker system prune -a -f

# Clean logs
sudo journalctl --vacuum-time=3d
```

## 8. Additional Resources

- [OCI Block Volume Documentation](https://docs.oracle.com/en-us/iaas/Content/Block/home.htm)
- [Docker Storage Best Practices](https://docs.docker.com/storage/)
- [Linux Filesystem Hierarchy](https://www.pathname.com/fhs/)

---

**Remember:** With this setup, even if your instance completely fails, your data remains safe on the block volume. You can always attach it to a new instance and continue working within minutes.
```

## File 2: Makefile (Verbose Version)

```makefile
# =====================================================================
#                    OCI BLOCK VOLUME SETUP MAKEFILE
# =====================================================================
# Purpose: Automate block volume setup to prevent data loss on OCI
# Author: System Administrator
# Date: January 2024
# Version: 2.0 (Verbose Edition)
#
# WHY THIS EXISTS:
# After weeks/months, OCI instances can fail with "Connection reset by peer"
# forcing you to recreate the instance and lose all data. This Makefile
# sets up a separate block volume for data persistence, so even if the
# instance fails, your data survives.
#
# USAGE:
#   make help     - Show all available commands
#   make all      - Run complete setup automatically
#   make check    - Check current system status
# =====================================================================

# ---------------------------------------------------------------------
# CONFIGURATION SECTION - Modify these if needed
# ---------------------------------------------------------------------
# Where to mount the block volume (default: /data)
MOUNT_POINT = /data

# Who should own the mounted volume (default: ubuntu:ubuntu)
# Change to opc:opc for Oracle Linux
VOLUME_OWNER = ubuntu:ubuntu

# Filesystem type (ext4 is most compatible)
FILESYSTEM_TYPE = ext4

# ---------------------------------------------------------------------
# AUTO

## Comprehensive Makefile for OCI Block Volume + Trading System Setup

Here's an enhanced, verbose Makefile that includes both block volume setup and your trading system deployment:

```makefile
# =====================================================================
# Universal Makefile for OCI Block Volume Setup + Trading System Deploy
# =====================================================================
# Works on: Oracle Linux 9, Ubuntu 24, Ubuntu 22.04
# Purpose: Automate block volume setup and trading system deployment
# Author: Trading System DevOps
# =====================================================================

# OS Detection and Environment Setup
OS_NAME := $(shell grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
OS_VERSION := $(shell grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
HOSTNAME := $(shell hostname)
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)

# OS-specific Configuration
ifeq ($(OS_NAME),ol)
    # Oracle Linux settings
    DEFAULT_USER = opc
    DEFAULT_GROUP = opc
    SUDO_GROUP = wheel
    SELINUX_ENABLED = true
    PACKAGE_MANAGER = dnf
else ifeq ($(OS_NAME),ubuntu)
    # Ubuntu settings
    DEFAULT_USER = ubuntu
    DEFAULT_GROUP = ubuntu
    SUDO_GROUP = sudo
    SELINUX_ENABLED = false
    PACKAGE_MANAGER = apt-get
else
    # Generic Linux settings
    DEFAULT_USER = $(shell whoami)
    DEFAULT_GROUP = $(shell whoami)
    SUDO_GROUP = sudo
    SELINUX_ENABLED = false
    PACKAGE_MANAGER = apt-get
endif

# Block Volume Configuration Variables
MOUNT_POINT = /data
VOLUME_OWNER = $(DEFAULT_USER):$(DEFAULT_GROUP)
FILESYSTEM_TYPE = ext4
DOCKER_DATA_DIR = $(MOUNT_POINT)/docker
TRADING_APP_DIR = $(MOUNT_POINT)/trading-app
BACKUP_DIR = $(MOUNT_POINT)/backups

# Auto-detected Block Device Variables
DEVICE := $(shell lsblk -rno NAME,TYPE | grep disk | grep -v -E 'sda|vda' | awk '{print "/dev/"$$1}' | head -1)
PARTITION := $(DEVICE)1
UUID := $(shell sudo blkid $(PARTITION) 2>/dev/null | grep -o 'UUID="[^"]*"' | cut -d'"' -f2)

# Trading System Configuration
TRADING_REPO_URL = https://github.com/your-org/trading-system.git
TRADING_BRANCH = main
CURRENCY_TO_BOOTSTRAP = BTC

# Docker Configuration
DOCKER_COMPOSE_VERSION = 2.23.0
DOCKER_NETWORK = trading-network

# ANSI Color codes for pretty output
GREEN = \033[0;32m
YELLOW = \033[1;33m
RED = \033[0;31m
BLUE = \033[0;34m
MAGENTA = \033[0;35m
CYAN = \033[0;36m
WHITE = \033[1;37m
NC = \033[0m # No Color

# Default target when just running 'make'
.DEFAULT_GOAL := help

# =======================
# HELP AND DOCUMENTATION
# =======================
.PHONY: help
help:
	@echo "$(BLUE)================================================================$(NC)"
	@echo "$(WHITE)   OCI Block Volume + Trading System Setup Makefile$(NC)"
	@echo "$(BLUE)================================================================$(NC)"
	@echo ""
	@echo "$(CYAN)System Information:$(NC)"
	@echo "  OS Detected    : $(GREEN)$(OS_NAME) $(OS_VERSION)$(NC)"
	@echo "  Hostname       : $(GREEN)$(HOSTNAME)$(NC)"
	@echo "  Default User   : $(GREEN)$(DEFAULT_USER)$(NC)"
	@echo "  Block Device   : $(GREEN)$(or $(DEVICE),NOT FOUND - Attach volume first!)$(NC)"
	@echo "  Mount Point    : $(GREEN)$(MOUNT_POINT)$(NC)"
	@echo ""
	@echo "$(CYAN)Quick Start Commands:$(NC)"
	@echo "  $(GREEN)make complete-setup$(NC)     - Run full setup (volume + trading system)"
	@echo "  $(GREEN)make volume-setup$(NC)       - Setup block volume only"
	@echo "  $(GREEN)make trading-setup$(NC)      - Setup trading system only"
	@echo ""
	@echo "$(CYAN)Block Volume Commands:$(NC)"
	@echo "  $(GREEN)make check$(NC)              - Check current disk status"
	@echo "  $(GREEN)make setup$(NC)              - Create partition on block device"
	@echo "  $(GREEN)make format$(NC)             - Format the volume ($(RED)DESTROYS DATA!$(NC))"
	@echo "  $(GREEN)make mount$(NC)              - Mount the volume temporarily"
	@echo "  $(GREEN)make permanent$(NC)          - Add to /etc/fstab for permanent mounting"
	@echo "  $(GREEN)make test$(NC)               - Test the volume setup"
	@echo ""
	@echo "$(CYAN)Trading System Commands:$(NC)"
	@echo "  $(GREEN)make install-docker$(NC)     - Install Docker and Docker Compose"
	@echo "  $(GREEN)make trading-deploy$(NC)     - Deploy trading application"
	@echo "  $(GREEN)make trading-bootstrap$(NC)  - Bootstrap trading system (first time)"
	@echo "  $(GREEN)make trading-unlock$(NC)     - Unlock system after verification"
	@echo "  $(GREEN)make trading-status$(NC)     - Check trading system status"
	@echo "  $(GREEN)make trading-logs$(NC)       - View trading system logs"
	@echo ""
	@echo "$(CYAN)Maintenance Commands:$(NC)"
	@echo "  $(GREEN)make backup$(NC)             - Create backup of data volume"
	@echo "  $(GREEN)make monitor$(NC)            - Install monitoring scripts"
	@echo "  $(GREEN)make clean-docker$(NC)       - Clean Docker artifacts ($(RED)CAUTION$(NC))"
	@echo "  $(GREEN)make disaster-recovery$(NC)  - Show disaster recovery procedures"
	@echo ""
	@echo "$(YELLOW)For detailed help on any command, run: make help-<command>$(NC)"
	@echo "$(YELLOW)Example: make help-format$(NC)"
	@echo "$(BLUE)================================================================$(NC)"

# =======================
# COMPLETE SETUP TARGETS
# =======================
.PHONY: complete-setup volume-setup trading-setup

complete-setup:
	@echo "$(BLUE)================================================================$(NC)"
	@echo "$(WHITE)         Complete OCI Instance Setup Starting...$(NC)"
	@echo "$(BLUE)================================================================$(NC)"
	@$(MAKE) volume-setup
	@echo ""
	@$(MAKE) install-docker
	@echo ""
	@$(MAKE) trading-setup
	@echo ""
	@echo "$(GREEN)✓ Complete setup finished successfully!$(NC)"
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "1. Create secret files: $(CYAN)make trading-secrets$(NC)"
	@echo "2. Bootstrap the system: $(CYAN)make trading-bootstrap$(NC)"
	@echo "3. Verify and unlock: $(CYAN)make trading-unlock$(NC)"

volume-setup: check setup format mount permanent selinux-fix test create-directories
	@echo "$(GREEN)✓ Block volume setup complete!$(NC)"

trading-setup: check-docker trading-deploy
	@echo "$(GREEN)✓ Trading system setup complete!$(NC)"

# =======================
# BLOCK VOLUME OPERATIONS
# =======================

.PHONY: check
check:
	@echo "$(YELLOW)=== Checking System Status ===$(NC)"
	@echo "$(CYAN)Available block devices:$(NC)"
	@lsblk -f
	@echo ""
	@echo "$(CYAN)Current disk usage:$(NC)"
	@df -h | grep -E "^/dev|^Filesystem" | grep -v tmpfs
	@echo ""
	@if [ -z "$(DEVICE)" ]; then \
		echo "$(RED)ERROR: No additional block device found!$(NC)"; \
		echo "$(YELLOW)Please attach a block volume in OCI Console first.$(NC)"; \
		echo ""; \
		echo "$(CYAN)Detected devices:$(NC)"; \
		lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep -v loop; \
		exit 1; \
	else \
		echo "$(GREEN)✓ Found device: $(DEVICE)$(NC)"; \
		echo "$(CYAN)Device details:$(NC)"; \
		sudo fdisk -l $(DEVICE) 2>/dev/null | grep -E "^Disk|^Device"; \
	fi

.PHONY: setup
setup: check
	@echo "$(YELLOW)=== Setting up Block Volume ===$(NC)"
	@echo "$(CYAN)This will prepare $(GREEN)$(DEVICE)$(NC) for use as a data volume$(NC)"
	@echo ""
	@if [ -e $(PARTITION) ]; then \
		echo "$(YELLOW)⚠ Partition $(PARTITION) already exists$(NC)"; \
		echo "$(CYAN)Current partition table:$(NC)"; \
		sudo fdisk -l $(DEVICE) | grep ^$(DEVICE); \
	else \
		echo "$(RED)WARNING: This will create a new partition table on $(DEVICE)!$(NC)"; \
		echo "$(YELLOW)All data on this device will be lost!$(NC)"; \
		read -p "Are you sure you want to continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1; \
		echo ""; \
		echo "$(CYAN)Creating partition...$(NC)"; \
		echo -e "n\np\n1\n\n\nw" | sudo fdisk $(DEVICE) > /dev/null 2>&1 || \
			(echo -e "g\nn\n1\n\n\nw" | sudo fdisk $(DEVICE) > /dev/null 2>&1); \
		sleep 2; \
		sudo partprobe $(DEVICE) 2>/dev/null || true; \
		echo "$(GREEN)✓ Partition created successfully$(NC)"; \
		echo "$(CYAN)New partition table:$(NC)"; \
		sudo fdisk -l $(DEVICE) | grep ^$(DEVICE); \
	fi

.PHONY: format
format: check
	@echo "$(YELLOW)=== Formatting Block Volume ===$(NC)"
	@if [ -e $(PARTITION) ]; then \
		if sudo blkid $(PARTITION) > /dev/null 2>&1; then \
			echo "$(YELLOW)⚠ WARNING: $(PARTITION) already contains a filesystem!$(NC)"; \
			echo "$(CYAN)Current filesystem info:$(NC)"; \
			sudo blkid $(PARTITION); \
			echo ""; \
			echo "$(RED)ALL DATA ON THIS PARTITION WILL BE PERMANENTLY DELETED!$(NC)"; \
			read -p "Are you absolutely sure you want to format? Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ] || exit 1; \
		fi; \
		echo ""; \
		echo "$(CYAN)Formatting $(PARTITION) as $(FILESYSTEM_TYPE)...$(NC)"; \
		sudo mkfs.$(FILESYSTEM_TYPE) -F -L "OCI-DATA" $(PARTITION); \
		sync; \
		echo "$(GREEN)✓ Formatted successfully$(NC)"; \
		echo "$(CYAN)New filesystem info:$(NC)"; \
		sudo blkid $(PARTITION); \
	else \
		echo "$(RED)ERROR: Partition $(PARTITION) not found!$(NC)"; \
		echo "$(YELLOW)Run 'make setup' first to create the partition$(NC)"; \
		exit 1; \
	fi

.PHONY: mount
mount:
	@echo "$(YELLOW)=== Mounting Block Volume ===$(NC)"
	@if [ ! -d $(MOUNT_POINT) ]; then \
		echo "$(CYAN)Creating mount point $(MOUNT_POINT)...$(NC)"; \
		sudo mkdir -p $(MOUNT_POINT); \
	fi
	@if mountpoint -q $(MOUNT_POINT); then \
		echo "$(YELLOW)⚠ $(MOUNT_POINT) is already mounted$(NC)"; \
		mount | grep $(MOUNT_POINT); \
	else \
		echo "$(CYAN)Mounting $(PARTITION) to $(MOUNT_POINT)...$(NC)"; \
		sudo mount $(PARTITION) $(MOUNT_POINT); \
		sudo chown $(VOLUME_OWNER) $(MOUNT_POINT); \
		echo "$(GREEN)✓ Mounted successfully$(NC)"; \
		echo "$(CYAN)Mount details:$(NC)"; \
		mount | grep $(MOUNT_POINT); \
	fi

.PHONY: permanent
permanent:
	@echo "$(YELLOW)=== Making Mount Permanent ===$(NC)"
	@# Refresh UUID after format
	$(




































