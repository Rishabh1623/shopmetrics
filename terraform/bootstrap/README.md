# Terraform Backend Bootstrap

## Why This Exists

Terraform needs a place to store its state file. We use S3 for storage and DynamoDB for locking to prevent concurrent modifications.

**These resources must be created BEFORE running `terraform init`.**

## Quick Start

### Option 1: Using the Script (Recommended)

```bash
# Make script executable
chmod +x create-backend.sh

# Run it
./create-backend.sh
```

### Option 2: Manual Creation

#### Create S3 Bucket

```bash
# Create bucket
aws s3api create-bucket \
  --bucket shopmetrics-terraform-state \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket shopmetrics-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket shopmetrics-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket shopmetrics-terraform-state \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

#### Create DynamoDB Table

```bash
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

## Alternative: Local State (For Testing)

If you want to use **local state** instead (not recommended for production), comment out the backend block in `terraform/main.tf`:

```hcl
# Comment out this entire block:
# backend "s3" {
#   bucket         = "shopmetrics-terraform-state"
#   key            = "observability/terraform.tfstate"
#   region         = "us-east-1"
#   encrypt        = true
#   dynamodb_table = "terraform-state-lock"
# }
```

Then Terraform will create a local `terraform.tfstate` file in your terraform directory.

## What Gets Created

1. **S3 Bucket**: `shopmetrics-terraform-state`
   - Stores the terraform.tfstate file
   - Versioning enabled (can recover from mistakes)
   - Encrypted at rest
   - Public access blocked

2. **DynamoDB Table**: `terraform-state-lock`
   - Prevents multiple people from modifying infrastructure simultaneously
   - Pay-per-request billing (very cheap, usually < $1/month)

## Cost

- **S3**: ~$0.023 per GB/month (state file is usually < 1MB)
- **DynamoDB**: ~$0.25 per million requests (you'll use maybe 100/month)
- **Total**: Less than $1/month

## After Creation

Once created, you can proceed with:

```bash
cd ../terraform
terraform init
terraform plan
terraform apply
```

## Troubleshooting

### Error: "bucket already exists"
The bucket name is globally unique. If someone else is using it, change the bucket name in:
- `terraform/main.tf` (backend block)
- `create-backend.sh` (BUCKET_NAME variable)

### Error: "Access Denied"
Make sure your AWS credentials have permissions to:
- Create S3 buckets
- Create DynamoDB tables
- Put bucket policies

### Want to use a different region?
Update the region in:
- `terraform/main.tf`
- `create-backend.sh`
- `terraform/variables.tf` (aws_region default)
