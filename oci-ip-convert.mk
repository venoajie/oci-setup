# Makefile for Converting OCI Ephemeral IP to Reserved IP
# Created: 2024-07-26
# 
# IMPORTANT LIMITATIONS DISCOVERED THROUGH TESTING:
# 1. OCI Web Console UI has changed - old button locations no longer exist as of 2024
# 2. Ephemeral IPs CANNOT be directly unassigned via CLI (returns InvalidParameter error)
# 3. Ephemeral IPs do NOT automatically release when instance is stopped
# 4. You CANNOT keep the same IP address when converting from ephemeral to reserved
# 5. The only working method is to DELETE the ephemeral IP, then assign a reserved IP

# Required environment variables - SET THESE FIRST
COMPARTMENT_ID ?= ocid1.tenancy.oc1..aaaaaaaapk5a76iob5ujd7byfio3cmfosyj363ogf4hjmti6zm5ojksexgzq
INSTANCE_NAME ?= instance-20250707-0704

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

.PHONY: help check-env list-instances get-instance-details check-current-ip convert-ip-interactive convert-ip-automated cleanup-reserved-ips verify-ip-count

help:
	@echo "OCI Ephemeral to Reserved IP Conversion Tool"
	@echo "============================================"
	@echo ""
	@echo "PREREQUISITES:"
	@echo "  1. OCI CLI installed and configured"
	@echo "  2. Run from OCI Cloud Shell or machine with OCI access"
	@echo "  3. Instance can be running or stopped"
	@echo ""
	@echo "TARGETS:"
	@echo "  make check-env               - Verify environment and OCI CLI"
	@echo "  make list-instances          - List all instances in compartment"
	@echo "  make get-instance-details    - Get details for specific instance"
	@echo "  make check-current-ip        - Check current IP configuration"
	@echo "  make convert-ip-interactive  - Convert IP with prompts (RECOMMENDED)"
	@echo "  make convert-ip-automated    - Convert IP without prompts"
	@echo "  make verify-ip-count         - Verify IP count matches instance count"
	@echo "  make cleanup-reserved-ips    - List unassigned reserved IPs"
	@echo ""
	@echo "USAGE:"
	@echo "  make INSTANCE_NAME=your-instance-name convert-ip-interactive"

check-env:
	@echo "$(YELLOW)Checking environment...$(NC)"
	@which oci > /dev/null || (echo "$(RED)ERROR: OCI CLI not found. Please install it first.$(NC)" && exit 1)
	@oci iam region list > /dev/null 2>&1 || (echo "$(RED)ERROR: OCI CLI not configured. Run 'oci setup config'$(NC)" && exit 1)
	@echo "$(GREEN)✓ OCI CLI is installed and configured$(NC)"
	@echo "Compartment ID: $(COMPARTMENT_ID)"
	@echo "Instance Name: $(INSTANCE_NAME)"

list-instances:
	@echo "$(YELLOW)Listing all instances in compartment...$(NC)"
	@oci compute instance list \
		--compartment-id $(COMPARTMENT_ID) \
		--query "data[*].[\"display-name\", id, \"lifecycle-state\"]" \
		--output table

get-instance-details:
	@echo "$(YELLOW)Getting instance details for: $(INSTANCE_NAME)$(NC)"
	@# AI/AUTOMATION NOTE: Instance name must match exactly, it's case-sensitive
	@INSTANCE_ID=$$(oci compute instance list \
		--compartment-id $(COMPARTMENT_ID) \
		--query "data[?\"display-name\"=='$(INSTANCE_NAME)'].id | [0]" \
		--raw-output); \
	if [ -z "$$INSTANCE_ID" ] || [ "$$INSTANCE_ID" = "null" ]; then \
		echo "$(RED)ERROR: Instance '$(INSTANCE_NAME)' not found$(NC)"; \
		echo "Run 'make list-instances' to see available instances"; \
		exit 1; \
	fi; \
	echo "Instance ID: $$INSTANCE_ID"; \
	echo ""; \
	oci compute instance get --instance-id $$INSTANCE_ID \
		--query "data.[\"display-name\", \"lifecycle-state\", \"shape\", \"availability-domain\"]"

check-current-ip:
	@echo "$(YELLOW)Checking current IP configuration for: $(INSTANCE_NAME)$(NC)"
	@# STEP 1: Get Instance ID
	@INSTANCE_ID=$$(oci compute instance list \
		--compartment-id $(COMPARTMENT_ID) \
		--query "data[?\"display-name\"=='$(INSTANCE_NAME)'].id | [0]" \
		--raw-output); \
	if [ -z "$$INSTANCE_ID" ] || [ "$$INSTANCE_ID" = "null" ]; then \
		echo "$(RED)ERROR: Instance not found$(NC)"; \
		exit 1; \
	fi; \
	\
	# STEP 2: Get VNIC Attachment (AI NOTE: Instances have VNIC attachments, not direct VNICs) \
	VNIC_ATTACHMENT_ID=$$(oci compute vnic-attachment list \
		--compartment-id $(COMPARTMENT_ID) \
		--instance-id $$INSTANCE_ID \
		--query "data[0].id" \
		--raw-output); \
	\
	# STEP 3: Get VNIC ID from attachment \
	VNIC_ID=$$(oci compute vnic-attachment get \
		--vnic-attachment-id $$VNIC_ATTACHMENT_ID \
		--query "data.\"vnic-id\"" \
		--raw-output); \
	\
	# STEP 4: Get current public IP from VNIC \
	echo ""; \
	echo "VNIC Information:"; \
	oci network vnic get --vnic-id $$VNIC_ID \
		--query "data.[\"display-name\", \"public-ip\", \"private-ip\"]"; \
	\
	# STEP 5: Get detailed public IP info (AI NOTE: Must check availability domain for ephemeral IPs) \
	AD=$$(oci compute instance get --instance-id $$INSTANCE_ID \
		--query "data.\"availability-domain\"" --raw-output); \
	echo ""; \
	echo "Public IP Details:"; \
	oci network public-ip list \
		--compartment-id $(COMPARTMENT_ID) \
		--scope AVAILABILITY_DOMAIN \
		--availability-domain "$$AD" \
		--all \
		--query "data[*].[\"ip-address\", \"lifetime\", \"lifecycle-state\", \"display-name\"]" \
		--output table

convert-ip-interactive:
	@echo "$(YELLOW)Starting Ephemeral to Reserved IP Conversion$(NC)"
	@echo "$(RED)WARNING: You will get a NEW IP address. The current IP will be lost!$(NC)"
	@echo "Press Enter to continue or Ctrl+C to cancel..."; \
	read dummy; \
	$(MAKE) convert-ip-automated

convert-ip-automated:
	@echo "$(YELLOW)Converting Ephemeral IP to Reserved IP for: $(INSTANCE_NAME)$(NC)"
	@# CRITICAL AI/AUTOMATION NOTES:
	@# 1. This process WILL change the public IP address
	@# 2. SSH connections will be lost during this process
	@# 3. Run from OCI Cloud Shell or external machine, NOT from the instance itself
	@# 4. The instance can be running or stopped - both states work
	@\
	@# Get Instance ID
	@INSTANCE_ID=$$(oci compute instance list \
		--compartment-id $(COMPARTMENT_ID) \
		--query "data[?\"display-name\"=='$(INSTANCE_NAME)'].id | [0]" \
		--raw-output); \
	\
	if [ -z "$$INSTANCE_ID" ] || [ "$$INSTANCE_ID" = "null" ]; then \
		echo "$(RED)ERROR: Instance not found$(NC)"; \
		exit 1; \
	fi; \
	\
	echo "Instance ID: $$INSTANCE_ID"; \
	\
	# Get VNIC information (AI NOTE: This is a multi-step process) \
	VNIC_ATTACHMENT_ID=$$(oci compute vnic-attachment list \
		--compartment-id $(COMPARTMENT_ID) \
		--instance-id $$INSTANCE_ID \
		--query "data[0].id" \
		--raw-output); \
	\
	VNIC_ID=$$(oci compute vnic-attachment get \
		--vnic-attachment-id $$VNIC_ATTACHMENT_ID \
		--query "data.\"vnic-id\"" \
		--raw-output); \
	\
	# Get Private IP ID (AI NOTE: Public IPs are assigned to Private IPs, not directly to VNICs) \
	PRIVATE_IP_ID=$$(oci network private-ip list \
		--vnic-id $$VNIC_ID \
		--query "data[0].id" \
		--raw-output); \
	\
	echo "Private IP ID: $$PRIVATE_IP_ID"; \
	\
	# Get Availability Domain (AI NOTE: Required for ephemeral IP operations) \
	AD=$$(oci compute instance get --instance-id $$INSTANCE_ID \
		--query "data.\"availability-domain\"" --raw-output); \
	\
	# Find current ephemeral IP (AI NOTE: Ephemeral IPs are scoped to availability domain) \
	EPHEMERAL_IP_ID=$$(oci network public-ip list \
		--compartment-id $(COMPARTMENT_ID) \
		--scope AVAILABILITY_DOMAIN \
		--availability-domain "$$AD" \
		--all \
		--query "data[?\"private-ip-id\"=='$$PRIVATE_IP_ID' && \"lifetime\"=='EPHEMERAL'].id | [0]" \
		--raw-output); \
	\
	if [ ! -z "$$EPHEMERAL_IP_ID" ] && [ "$$EPHEMERAL_IP_ID" != "null" ]; then \
		CURRENT_IP=$$(oci network public-ip get --public-ip-id $$EPHEMERAL_IP_ID \
			--query "data.\"ip-address\"" --raw-output); \
		echo "Current Ephemeral IP: $$CURRENT_IP (will be deleted)"; \
		echo ""; \
		echo "$(YELLOW)Step 1: Deleting ephemeral IP...$(NC)"; \
		# AI NOTE: This is the ONLY way to remove ephemeral IPs - deletion \
		# Attempting to unassign with --private-ip-id "" will fail with InvalidParameter \
		oci network public-ip delete --public-ip-id $$EPHEMERAL_IP_ID --force || \
			(echo "$(RED)ERROR: Failed to delete ephemeral IP$(NC)" && exit 1); \
		echo "$(GREEN)✓ Ephemeral IP deleted$(NC)"; \
	else \
		echo "No ephemeral IP found (instance might already have reserved IP)"; \
	fi; \
	\
	echo ""; \
	echo "$(YELLOW)Step 2: Creating reserved public IP...$(NC)"; \
	# AI NOTE: Reserved IPs are scoped to REGION, not availability domain \
	RESERVED_IP_ID=$$(oci network public-ip create \
		--compartment-id $(COMPARTMENT_ID) \
		--lifetime RESERVED \
		--display-name "Reserved-IP-$(INSTANCE_NAME)" \
		--wait-for-state AVAILABLE \
		--query "data.id" \
		--raw-output); \
	\
	if [ -z "$$RESERVED_IP_ID" ] || [ "$$RESERVED_IP_ID" = "null" ]; then \
		echo "$(RED)ERROR: Failed to create reserved IP$(NC)"; \
		exit 1; \
	fi; \
	\
	NEW_IP=$$(oci network public-ip get --public-ip-id $$RESERVED_IP_ID \
		--query "data.\"ip-address\"" --raw-output); \
	echo "$(GREEN)✓ Reserved IP created: $$NEW_IP$(NC)"; \
	\
	echo ""; \
	echo "$(YELLOW)Step 3: Assigning reserved IP to instance...$(NC)"; \
	# AI NOTE: This assignment will work even if instance is running \
	oci network public-ip update \
		--public-ip-id $$RESERVED_IP_ID \
		--private-ip-id $$PRIVATE_IP_ID \
		--wait-for-state ASSIGNED || \
		(echo "$(RED)ERROR: Failed to assign reserved IP$(NC)" && exit 1); \
	\
	echo "$(GREEN)✓ Reserved IP assigned successfully$(NC)"; \
	echo ""; \
	echo "$(GREEN)CONVERSION COMPLETE!$(NC)"; \
	echo "New Reserved IP: $$NEW_IP"; \
	echo ""; \
	echo "$(YELLOW)Next steps:$(NC)"; \
	echo "1. Update SSH: ssh opc@$$NEW_IP"; \
	echo "2. Update any DNS records pointing to old IP"; \
	echo "3. Update firewall rules if needed"

verify-ip-count:
	@echo "$(YELLOW)Verifying IP count matches instance count...$(NC)"
	@echo ""
	@# Count running instances
	@INSTANCE_COUNT=$$(oci compute instance list \
		--compartment-id $(COMPARTMENT_ID) \
		--all \
		--query "length(data[?\"lifecycle-state\"=='RUNNING'])" \
		--raw-output); \
	echo "Running Instances: $$INSTANCE_COUNT"; \
	\
	# Count reserved IPs (both assigned and unassigned) \
	RESERVED_COUNT=$$(oci network public-ip list \
		--compartment-id $(COMPARTMENT_ID) \
		--scope REGION \
		--lifetime RESERVED \
		--all \
		--query "length(data)" \
		--raw-output); \
	echo "Reserved IPs: $$RESERVED_COUNT"; \
	\
	# Count unassigned reserved IPs (these cost money!) \
	UNASSIGNED_COUNT=$$(oci network public-ip list \
		--compartment-id $(COMPARTMENT_ID) \
		--scope REGION \
		--lifetime RESERVED \
		--all \
		--query "length(data[?\"lifecycle-state\"=='AVAILABLE'])" \
		--raw-output); \
	echo "Unassigned Reserved IPs: $$UNASSIGNED_COUNT"; \
	\
	echo ""; \
	if [ "$$UNASSIGNED_COUNT" -gt "0" ]; then \
		echo "$(RED)WARNING: You have $$UNASSIGNED_COUNT unassigned reserved IP(s) that are being charged!$(NC)"; \
		echo "Run 'make cleanup-reserved-ips' to see details"; \
	else \
		echo "$(GREEN)✓ No unassigned reserved IPs (no extra charges)$(NC)"; \
	fi; \
	\
	# Check for instances without reserved IPs \
	echo ""; \
	echo "$(YELLOW)Checking which instances have which type of public IP...$(NC)"; \
	$(MAKE) audit-all-ips

audit-all-ips:
	@echo "$(YELLOW)Auditing all instances and their public IPs...$(NC)"
	@# AI NOTE: This is complex because we need to check both ephemeral and reserved IPs
	@# and correlate them with instances
	@for instance_id in $$(oci compute instance list \
		--compartment-id $(COMPARTMENT_ID) \
		--all \
		--query "data[?\"lifecycle-state\"=='RUNNING'].id" \
		--raw-output); do \
		\
		INSTANCE_NAME=$$(oci compute instance get \
			--instance-id $$instance_id \
			--query "data.\"display-name\"" \
			--raw-output); \
		\
		echo ""; \
		echo "Instance: $$INSTANCE_NAME"; \
		\
		# Get VNIC info \
		VNIC_ID=$$(oci compute vnic-attachment list \
			--compartment-id $(COMPARTMENT_ID) \
			--instance-id $$instance_id \
			--query "data[0].\"vnic-id\"" \
			--raw-output); \
		\
		if [ ! -z "$$VNIC_ID" ] && [ "$$VNIC_ID" != "null" ]; then \
			PUBLIC_IP=$$(oci network vnic get \
				--vnic-id $$VNIC_ID \
				--query "data.\"public-ip\"" \
				--raw-output); \
			\
			if [ ! -z "$$PUBLIC_IP" ] && [ "$$PUBLIC_IP" != "null" ]; then \
				echo "  Public IP: $$PUBLIC_IP"; \
				\
				# Determine if it's ephemeral or reserved \
				IP_TYPE=$$(oci network public-ip list \
					--compartment-id $(COMPARTMENT_ID) \
					--scope REGION \
					--all \
					--query "data[?\"ip-address\"=='$$PUBLIC_IP'].lifetime | [0]" \
					--raw-output); \
				\
				if [ "$$IP_TYPE" = "RESERVED" ]; then \
					echo "  Type: $(GREEN)RESERVED (Persistent)$(NC)"; \
				else \
					# Check in availability domain for ephemeral \
					AD=$$(oci compute instance get --instance-id $$instance_id \
						--query "data.\"availability-domain\"" --raw-output); \
					IP_TYPE=$$(oci network public-ip list \
						--compartment-id $(COMPARTMENT_ID) \
						--scope AVAILABILITY_DOMAIN \
						--availability-domain "$$AD" \
						--all \
						--query "data[?\"ip-address\"=='$$PUBLIC_IP'].lifetime | [0]" \
						--raw-output); \
					if [ "$$IP_TYPE" = "EPHEMERAL" ]; then \
						echo "  Type: $(YELLOW)EPHEMERAL (Will change on stop/start)$(NC)"; \
						echo "  $(YELLOW)→ Consider converting to reserved IP$(NC)"; \
					fi; \
				fi; \
			else \
				echo "  Public IP: $(RED)None$(NC)"; \
			fi; \
		fi; \
	done

cleanup-reserved-ips:
	@echo "$(YELLOW)Checking for unassigned reserved IPs...$(NC)"
	@echo "$(RED)Unassigned reserved IPs cost money!$(NC)"
	@echo ""
	@oci network public-ip list \
		--compartment-id $(COMPARTMENT_ID) \
		--scope REGION \
		--lifetime RESERVED \
		--all \
		--query "data[?\"lifecycle-state\"=='AVAILABLE'].[\"display-name\", \"ip-address\", id, \"time-created\"]" \
		--output table
	@echo ""
	@echo "To delete an unassigned reserved IP:"
	@echo "oci network public-ip delete --public-ip-id <PUBLIC-IP-OCID> --force"


.PHONY: audit-all-ips show-ephemeral-ips convert-all-to-reserved backup-ip-config

show-ephemeral-ips:
	@echo "$(YELLOW)Checking for instances with ephemeral IPs...$(NC)"
	@# This helps identify which instances still need conversion
	@for instance_id in $$(oci compute instance list \
		--compartment-id $(COMPARTMENT_ID) \
		--all \
		--query "data[?\"lifecycle-state\"=='RUNNING'].id" \
		--raw-output); do \
		\
		INSTANCE_NAME=$$(oci compute instance get \
			--instance-id $$instance_id \
			--query "data.\"display-name\"" \
			--raw-output); \
		\
		AD=$$(oci compute instance get --instance-id $$instance_id \
			--query "data.\"availability-domain\"" --raw-output); \
		\
		# Get VNIC attachment and ID \
		VNIC_ID=$$(oci compute vnic-attachment list \
			--compartment-id $(COMPARTMENT_ID) \
			--instance-id $$instance_id \
			--query "data[0].\"vnic-id\"" \
			--raw-output); \
		\
		# Get private IP \
		PRIVATE_IP_ID=$$(oci network private-ip list \
			--vnic-id $$VNIC_ID \
			--query "data[0].id" \
			--raw-output); \
		\
		# Check for ephemeral IP \
		EPHEMERAL_IP=$$(oci network public-ip list \
			--compartment-id $(COMPARTMENT_ID) \
			--scope AVAILABILITY_DOMAIN \
			--availability-domain "$$AD" \
			--all \
			--query "data[?\"private-ip-id\"=='$$PRIVATE_IP_ID' && \"lifetime\"=='EPHEMERAL'].\"ip-address\" | [0]" \
			--raw-output); \
		\
		if [ ! -z "$$EPHEMERAL_IP" ] && [ "$$EPHEMERAL_IP" != "null" ]; then \
			echo "$(YELLOW)Instance: $$INSTANCE_NAME - Ephemeral IP: $$EPHEMERAL_IP$(NC)"; \
		fi; \
	done

convert-all-to-reserved:
	@echo "$(YELLOW)Converting ALL ephemeral IPs to reserved IPs$(NC)"
	@echo "$(RED)WARNING: This will change ALL public IPs for instances with ephemeral IPs!$(NC)"
	@echo "Press Enter to continue or Ctrl+C to cancel..."; \
	read dummy; \
	@# Find and convert all ephemeral IPs
	@for instance_id in $$(oci compute instance list \
		--compartment-id $(COMPARTMENT_ID) \
		--all \
		--query "data[?\"lifecycle-state\"=='RUNNING'].id" \
		--raw-output); do \
		\
		INSTANCE_NAME=$$(oci compute instance get \
			--instance-id $$instance_id \
			--query "data.\"display-name\"" \
			--raw-output); \
		\
		echo ""; \
		echo "Checking $$INSTANCE_NAME..."; \
		$(MAKE) INSTANCE_NAME=$$INSTANCE_NAME convert-ip-automated || true; \
	done

backup-ip-config:
	@echo "$(YELLOW)Backing up current IP configuration...$(NC)"
	@BACKUP_FILE="oci-ip-backup-$$(date +%Y%m%d-%H%M%S).json"
	@echo "Saving to: $$BACKUP_FILE"
	@# Create a comprehensive backup of all IP configurations
	@echo "{" > $$BACKUP_FILE
	@echo "  \"backup_date\": \"$$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> $$BACKUP_FILE
	@echo "  \"compartment_id\": \"$(COMPARTMENT_ID)\"," >> $$BACKUP_FILE
	@echo "  \"instances\": [" >> $$BACKUP_FILE
	@FIRST=true; \
	for instance_id in $$(oci compute instance list \
		--compartment-id $(COMPARTMENT_ID) \
		--all \
		--query "data[*].id" \
		--raw-output); do \
		\
		if [ "$$FIRST" != "true" ]; then echo "," >> $$BACKUP_FILE; fi; \
		FIRST=false; \
		\
		INSTANCE_DATA=$$(oci compute instance get \
			--instance-id $$instance_id \
			--query "data.{name:\"display-name\", id:id, state:\"lifecycle-state\", ad:\"availability-domain\"}"); \
		\
		# Get VNIC and IP info \
		VNIC_ID=$$(oci compute vnic-attachment list \
			--compartment-id $(COMPARTMENT_ID) \
			--instance-id $$instance_id \
			--query "data[0].\"vnic-id\"" \
			--raw-output 2>/dev/null || echo "null"); \
		\
		PUBLIC_IP="null"; \
		IP_TYPE="null"; \
		if [ "$$VNIC_ID" != "null" ]; then \
			PUBLIC_IP=$$(oci network vnic get \
				--vnic-id $$VNIC_ID \
				--query "data.\"public-ip\"" \
				--raw-output 2>/dev/null || echo "null"); \
		fi; \
		\
		echo -n "    {" >> $$BACKUP_FILE; \
		echo -n "\"instance\": $$INSTANCE_DATA, " >> $$BACKUP_FILE; \
		echo -n "\"public_ip\": \"$$PUBLIC_IP\"" >> $$BACKUP_FILE; \
		echo -n "}" >> $$BACKUP_FILE; \
	done
	@echo "" >> $$BACKUP_FILE
	@echo "  ]" >> $$BACKUP_FILE
	@echo "}" >> $$BACKUP_FILE
	@echo "$(GREEN)✓ Backup saved to: $$BACKUP_FILE$(NC)"

# Add to help target (update the existing help target):
help:
	@echo "OCI Ephemeral to Reserved IP Conversion Tool"
	@echo "============================================"
	@echo ""
	@echo "PREREQUISITES:"
	@echo "  1. OCI CLI installed and configured"
	@echo "  2. Run from OCI Cloud Shell or machine with OCI access"
	@echo "  3. Instance can be running or stopped"
	@echo ""
	@echo "TARGETS:"
	@echo "  make check-env               - Verify environment and OCI CLI"
	@echo "  make list-instances          - List all instances in compartment"
	@echo "  make get-instance-details    - Get details for specific instance"
	@echo "  make check-current-ip        - Check current IP configuration"
	@echo "  make show-ephemeral-ips      - Show only instances with ephemeral IPs"
	@echo "  make convert-ip-interactive  - Convert IP with prompts (RECOMMENDED)"
	@echo "  make convert-ip-automated    - Convert IP without prompts"
	@echo "  make convert-all-to-reserved - Convert ALL ephemeral IPs to reserved"
	@echo "  make verify-ip-count         - Verify IP count matches instance count"
	@echo "  make audit-all-ips           - Detailed audit of all IPs"
	@echo "  make cleanup-reserved-ips    - List unassigned reserved IPs"
	@echo "  make backup-ip-config        - Backup current IP configuration to JSON"
	@echo ""
	@echo "USAGE EXAMPLES:"
	@echo "  make INSTANCE_NAME=your-instance-name convert-ip-interactive"
	@echo "  make show-ephemeral-ips"
	@echo "  make backup-ip-config"

# AI/AUTOMATION TROUBLESHOOTING NOTES:
# 
# COMMON ERRORS AND SOLUTIONS:
# 
# 1. "InvalidParameter: Ephemeral public IP cannot be moved or unassigned"
#    SOLUTION: Must DELETE the ephemeral IP, not unassign it
#    CORRECT: oci network public-ip delete --public-ip-id <ID> --force
#    WRONG: oci network public-ip update --public-ip-id <ID> --private-ip-id ""
#
# 2. "Conflict: Private IP already has a public IP assigned"
#    SOLUTION: Delete the existing ephemeral IP first before assigning reserved IP
#
# 3. "Instance not found"
#    SOLUTION: Instance names are case-sensitive, verify exact name with 'make list-instances'
#
# 4. Web Console method not working
#    ISSUE: As of 2024, OCI Console UI has changed, old "Edit" button for IPs may not exist
#    SOLUTION: Use CLI method with deletion approach
#
# 5. SSH connection lost during conversion
#    SOLUTION: Run commands from OCI Cloud Shell or external machine, not from the instance itself
#
# ARCHITECTURE NOTES FOR AI:
# - Public IPs are assigned to Private IPs, not directly to instances or VNICs
# - Ephemeral IPs are scoped to Availability Domain
# - Reserved IPs are scoped to Region
# - VNICs are attached to instances via VNIC Attachments
# - Each VNIC has one primary Private IP
# - Each Private IP can have at most one Public IP

#commands:
#make -f oci-ip-convert.mk help
#make -f oci-ip-convert.mk verify-ip-count
#make -f oci-ip-convert.mk audit-all-ips
