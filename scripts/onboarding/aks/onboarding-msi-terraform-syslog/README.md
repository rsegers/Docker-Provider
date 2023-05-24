If you are deploying a new AKS cluster using Terraform with ama logs addon enabled, follow the steps below.

1. Please download all files under AddonTerraformTemplate.
2. Update variables.tf to replace values in "<>"
3. Run `terraform init -upgrade` to initialize the Terraform deployment.
4. Run `terraform plan -out main.tfplan` to initialize the Terraform deployment.
5. Run `terraform apply main.tfplan` to apply the execution plan to your cloud infrastructure.

**NOTE**
- Please edit the main.tf file appropriately before running the terraform template
