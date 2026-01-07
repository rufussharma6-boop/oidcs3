provider "aws" {
  region = "ap-south-1" 
}

# 1. OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# 2. S3 Buckets
resource "aws_s3_bucket" "web_bucket" {
  for_each      = toset(["dev", "prod"])
  bucket        = "prabhats3bucket${each.key}"
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "config" {
  for_each = aws_s3_bucket.web_bucket
  bucket   = each.value.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  for_each = aws_s3_bucket.web_bucket
  bucket   = each.value.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 3. S3 Bucket Policy
resource "aws_s3_bucket_policy" "read_policy" {
  for_each = aws_s3_bucket.web_bucket
  bucket   = each.value.id
  
  depends_on = [aws_s3_bucket_public_access_block.public_access]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicRead"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${each.value.arn}/*"
    }]
  })
}

# 4. IAM Roles
resource "aws_iam_role" "github_role" {
  for_each = toset(["dev", "prod"])
  name     = "github-deploy-role-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { 
          # !!! REPLACE YOUR_USER/YOUR_REPO BELOW !!!
          "token.actions.githubusercontent.com:sub" = "repo:rufussharma6-boop/oidcs3:ref:refs/heads/${each.key == "prod" ? "main" : "dev"}" 
        }
      }
    }]
  })
}

# 5. IAM Policy
resource "aws_iam_role_policy" "deploy_policy" {
  for_each = aws_iam_role.github_role

  name = "S3DeployPolicy"
  role = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:ListBucket", "s3:DeleteObject"]
      Resource = [
        "arn:aws:s3:::prabhats3bucket${each.key}",
        "arn:aws:s3:::prabhats3bucket${each.key}/*"
      ]
    }]
  })
}

# 6. Outputs
output "role_arns" {
  value = { for k, v in aws_iam_role.github_role : k => v.arn }
}
