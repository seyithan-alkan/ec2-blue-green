# Blue-Green Deployment on AWS EC2 with Terraform and GitHub Actions

This project showcases an automated blue-green deployment strategy on AWS, leveraging Terraform for infrastructure management and GitHub Actions for continuous integration and deployment workflows. The setup automates the provisioning of AWS resources including VPC, subnets, EC2 instances, AWS Secret Manager, and S3 buckets. It ensures zero downtime and seamless transition between application versions by dynamically adjusting weights in AWS target groups.

## Prerequisites

- AWS account
- GitHub account with a repository for the project
- Proper AWS permissions configured for GitHub Actions to deploy and manage AWS resources

## GitHub Actions Workflow

The `blue-green.yml` workflow automates the deployment process upon a push to the repository, encompassing:

1. **Terraform Setup:** Initialization and application of Terraform configurations to set up or update AWS infrastructure.
2. **Configuration and Deployment:**
   - EC2 instances are automatically configured with the necessary software using user-data scripts.
   - The blue-green deployment is facilitated by modifying weights in AWS target groups, based on configurations in `actions.json` and `conditions.json`.

## Workflow Details

- **Terraform Configuration:** `main.tf` and `variable.tf` define the AWS infrastructure. Adjust these files to meet your project's needs.
- **Scripts for Deployment:**
  - `setup-script.ps1` for configuring IIS and the GitHub Actions runner on EC2 instances.
  - `blue-deploy.ps1` and `green-deploy.ps1` for managing the blue-green deployment.

## Configuration Files

- **GitHub Actions (`blue-green.yml`):** Defines the CI/CD pipeline.
- **Deployment Strategies (`actions.json` and `conditions.json`):** Configures the target groups for deployment, including their weights and routing conditions.

## Getting Started

Fork or clone the repository to begin. Ensure AWS credentials for GitHub Actions are set up correctly and update Terraform and script files as necessary for your infrastructure requirements.

## Contributions

We welcome contributions. Please fork the repository, make your changes, and submit a pull request.


