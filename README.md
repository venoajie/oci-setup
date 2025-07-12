# oci-setup

OCI Instance
├── Boot Volume (30GB) - OS only, can be recreated
│ ├── /boot
│ ├── /etc
│ └── /var (except Docker)
└── Block Volume (50-200GB) - Your persistent data
├── /data/docker - Docker data directory
├── /data/apps - Application data
├── /data/backups - Local backups
└── /data/logs - Persistent logs


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

Step 2.2: One-Command Setup (Recommended)
For a complete automated setup:

# This will partition, format, mount, and configure the block volume
make all

What happens:

Creates partition on the attached block device
Formats it as ext4 filesystem
Mounts to /data
Adds to /etc/fstab for persistence
Tests read/write access

Step 2.3: Manual Step-by-Step (If Needed)
If you prefer to run each step individually:

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

Step 2.4: Post-Setup Configuration

# Install monitoring scripts
make monitor

# Create backup scripts
make backup

# View current configuration
make info

3. Docker and Application Setup
Step 3.1: Move Docker to Block Volume

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

Step 3.2: Application Deployment Example
Here's an example for deploying a trading application:

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

4. Daily Operations and Maintenance
Monitoring Disk Usage

# Quick check
make status

# Detailed usage
df -h /data
du -sh /data/*

# Find large files
find /data -type f -size +100M -exec ls -lh {} \;


Backup Procedures

# Manual backup
make backup

# Schedule automatic backups (add to crontab)
crontab -e
# Add: 0 2 * * * cd /home/ubuntu && make backup

Docker Cleanup (Regular Maintenance)
# Remove unused Docker data
docker system prune -a -f

# Check Docker space usage
docker system df

# Clean old logs
find /data/logs -name "*.log" -mtime +30 -delete

 Disaster Recovery Procedures
Scenario 1: SSH Connection Lost

# 1. Try OCI Console Connection (no SSH needed)
# OCI Console → Instance → Console Connection → Create

# 2. Once connected via console:
df -h                      # Check if disk full
systemctl status sshd      # Check SSH service
journalctl -xe            # Check system logs

# 3. Common fixes:
sudo journalctl --vacuum-time=7d    # Clean logs
sudo systemctl restart sshd          # Restart SSH

Scenario 2: Instance Won't Boot

# 1. Stop instance (don't terminate!)
# 2. Detach boot volume
# 3. Your data is safe on block volume!
# 4. Create new instance
# 5. Attach block volume to new instance
# 6. Run: make mount
# 7. Continue working with your data intact

Scenario 3: Restore from Backup
# List available backups
ls -la /data/backups/

# Restore specific backup
cd /
sudo tar -xzf /data/backups/data-20240115-020000.tar.gz

6. Best Practices
Never store critical data on boot volume

Boot volume = OS only
Block volume = All your data
Regular maintenance

Run docker system prune weekly
Check disk usage daily
Test backups monthly
Monitor proactively

Set up disk usage alerts
Watch system logs
Keep 20% free space
Document everything

Keep this README updated
Document any custom configurations
Note any issues and solutions
7. Troubleshooting
Block Volume Not Found

# Check if volume is attached in OCI Console
# Then run:
lsblk
# Look for unpartitioned disk (usually /dev/sdb)

Mount Fails After Reboot

# Check /etc/fstab entry
cat /etc/fstab | grep data

# Test mount
sudo mount -a

# Check for errors
dmesg | tail

Disk Full Errors

# Find what's using space
du -h /data | sort -rh | head -20

# Clean Docker
docker system prune -a -f

# Clean logs
sudo journalctl --vacuum-time=3d
