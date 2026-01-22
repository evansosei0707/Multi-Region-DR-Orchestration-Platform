# Secure Database Initialization with Bastion Host

## Overview

This approach uses a temporary EC2 bastion host in your public subnet to initialize the database. It's secure, Terraform-managed, and automatically runs the initialization on boot.

## Benefits

✅ **Secure** - Bastion in public subnet, RDS stays private  
✅ **Terraform-managed** - No manual AWS CLI changes  
✅ **Automatic** - Runs init script on first boot via user-data  
✅ **Temporary** - Destroy after use  
✅ **No SSH key needed** - Init runs automatically  

## Step 1: Add Bastion Module

Add this to `terraform/main.tf` (at the end, before the closing brace):

```hcl
# Temporary bastion for database initialization
module "bastion" {
  source = "./modules/bastion"

  providers = {
    aws = aws.primary
  }

  project_name          = var.project_name
  region_name           = "primary"
  vpc_id                = module.networking_primary.vpc_id
  public_subnet_id      = module.networking_primary.public_subnet_ids[0]
  rds_security_group_id = module.networking_primary.rds_security_group_id
  your_ip_cidr          = var.bastion_ip_cidr
}

output "bastion_ip" {
  value = module.bastion.bastion_public_ip
}
```

## Step 2: Apply Terraform

```bash
cd terraform
terraform init  # Initialize the new bastion module
terraform plan
terraform apply
```

The bastion will:
1. Launch in the public subnet
2. Install PostgreSQL client automatically
3. Fetch DB credentials from Secrets Manager
4. Run the initialization SQL
5. Log results to `/var/log/db-init.log`

## Step 3: Verify Initialization (Optional)

Check if initialization succeeded:

```bash
# Get bastion IP from terraform output
BASTION_IP=$(terraform output -raw bastion_ip)

# View initialization logs (requires SSH key)
# If you don't have a key, skip this - the init runs automatically anyway
ssh -i your-key.pem ec2-user@$BASTION_IP 'cat /var/log/db-init.log'
```

Or check the database directly from another method later.

## Step 4: Destroy Bastion

After initialization (wait ~5 minutes for user-data to complete):

Remove the bastion module from `main.tf` or comment it out, then:

```bash
terraform apply
```

This will destroy the bastion host, keeping your infrastructure secure.

## Alternative: Use Systems Manager Session Manager

If you don't want to open SSH (port 22), you can use SSM Session Manager instead. The bastion automatically has the IAM role needed. Just add SSM permissions and connect via AWS Console.

## Troubleshooting

**Database not initialized?**
- Wait 5-10 minutes after bastion creation (user-data takes time)
- Check CloudWatch Logs or SSH to bastion to view `/var/log/db-init.log`

**Can't connect to bastion?**
- Verify `bastion_ip_cidr` in terraform.tfvars matches your IP
- Check security group allows SSH from your IP

---

**This is the recommended secure approach for database initialization!**
