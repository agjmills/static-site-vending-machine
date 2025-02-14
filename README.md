# Terraform Configuration README

This Terraform configuration sets up infrastructure for hosting a static website using AWS and Cloudflare. It includes creating an S3 bucket for website hosting, securing the site with SSL using AWS Certificate Manager, and delivering the content through CloudFront. DNS records are managed in Cloudflare.

---

## Prerequisite

The domain you plan to use must be registered and managed in Cloudflare.

---

## How to Use the Workflow

This repository includes a GitHub Actions workflow to automate the deployment process. The workflow is triggered manually using the `workflow_dispatch` event and requires the domain name as an input.

### Steps:

1. **Trigger the Workflow**  
   Go to the "Actions" tab in your GitHub repository. Select the "Terraform Workflow with Domain" workflow and click "Run Workflow." Enter the domain name as input.

2. **Workflow Execution**  
   The workflow will:
   - Checkout the repository.
   - Initialize Terraform with backend configurations.
   - Run `terraform plan` to generate an execution plan.
   - Run `terraform apply` to provision the infrastructure.

3. **Deployment Completion**  
   Once the workflow finishes, your static website will be live on the specified domain.