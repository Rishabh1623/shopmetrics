# Terraform Backend Setup

## Purpose

This directory contains Terraform configuration to create the backend infrastructure (S3 bucket and DynamoDB table) needed to store Terraform state for the main project.

## Why This Exists

Terraform needs a backend to store its state file. This is a "chicken and egg" problem:
- Main Terraform needs backend to work
- But backend must exist first
- So we create backend separately

## What Gets Created

1. **S3 Bucket:** `shopmetrics-terraform-state`
   - Stores Terraform state file
   - Versioning enabled (can recover from mistakes)
   - Encryption enabled (security)
   - Public access blocked

2. **DynamoDB Table:** `terraform-state-lock`
   - Prevents concurrent Terraform runs
   - Ensures state consistency
   - Pay-per-request billing (~$0.40/month)

## Usage

### Create Backend (One-Time Setup)

```bash
cd terraform/backend-setup

# Initialize Terraform
terraform init

# Create backend resources
terraform apply
```

### After Backend is Created

```bash
# Go to main terraform directory
cd ..

# Now you can use main Terraform
terraform init
terraform apply
```

## Important Notes

- ⚠️ Run this ONLY ONCE per project
- ⚠️ This uses LOCAL state (not remote)
- ⚠️ Keep the local state file safe
- ⚠️ Don't delete backend while main infrastructure exists

## Cost

- S3 Storage: ~$0.10/month
- DynamoDB: ~$0.40/month
- **Total: ~$0.50/month**

## Cleanup

To delete backend (only after destroying main infrastructure):

```bash
cd terraform/backend-setup
terraform destroy
```

## Troubleshooting

### Error: Bucket already exists

The bucket name must be globally unique. If someone else is using it, change the `project_name` variable.

### Error: Access Denied

Ensure your AWS credentials have permissions to:
- Create S3 buckets
- Create DynamoDB tables
- Manage bucket policies

## Alternative Approach

If you prefer using AWS CLI instead of Terraform, use the script in `terraform/bootstrap/create-backend.sh`.
