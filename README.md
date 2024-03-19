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

## Notes

- **Self-Hosted Runner Setup Time:** The setup of self-hosted runners using user-data can take a considerable amount of time. These runners will automatically appear under the repository's Actions settings once the setup is complete, enabling the execution of `deploy-green` and `deploy-blue` jobs.
- **Public Repositories:** If this setup is used with public repositories, ensure to grant the necessary permissions for self-hosted runners to execute workflows on public repositories through the repository's GitHub Actions settings.

## Getting Started

Fork or clone the repository to begin. Ensure AWS credentials for GitHub Actions are set up correctly and update Terraform and script files as necessary for your infrastructure requirements.

## Secrets:
** AWS_ACCESS_KEY_ID
** AWS_SECRET_ACCESS_KEY
** GH_ACTION_TOKEN
** SEYITHAN_PFX (convert .pfx file to base64)
** SEYITHAN_PFX_SECRET (secret for your pfx file as plaintext)

## Status Code during Deploymnet

Check the link below:

https://app.warp.dev/block/MPOTPsWg4EpdhYOWdcEFfo

## Screenshots

![ec2-instances](https://drive.google.com/thumbnail?id=1yo_vHsrANGFtw-G9DqY8IVYFvmvQyL4_&sz=w1000) 
![ALB-Listeners](https://drive.google.com/thumbnail?id=1BVNASjwgq9rMyCbPzvR2AF6m_UoZx4qe&sz=w1000) 
![Target-Groups](https://drive.google.com/thumbnail?id=1LjcSG3Cy7nW72cPRqjEIa3wpYOl-utvI&sz=w1000) 
![targets](https://drive.google.com/thumbnail?id=1xMsSK2LgHjzC0EIkNTpczZIjNkmHIH2l&sz=w1000) 
![iis-setup](https://drive.google.com/thumbnail?id=1Wi6UNd0OJgg5bNJ1c60l-Y4EVncmeHKU&sz=w1000) 
![deploy-green](https://drive.google.com/thumbnail?id=1S0ByJxeSudH2nC2UrHrU9U8wbUNbiv73&sz=w1000) 
![deploy-blue](https://drive.google.com/thumbnail?id=1SIRLRiprxt8xCaIwgaDmwGkoehO3eR-R&sz=w1000) 
![deploy-complete](https://drive.google.com/thumbnail?id=1BlUgK3zHNox3rJRu39AYoz57yx6ccr3M&sz=w1000) 
![runners](https://drive.google.com/thumbnail?id=1xC78VGEqAGwHlJ5czpdBNIpTI5QhFzRH&sz=w1000) 
![workflow](https://drive.google.com/thumbnail?id=1GfV5dbbTjo7KEz-_yWHY4LArRA5v1qWG&sz=w1000) 
![deployment](https://drive.google.com/thumbnail?id=1ZHOTeRKXgbZ_T02uZ1ONV8_ofB6mQZip&sz=w1000) 

## Contributions

We welcome contributions. Please fork the repository, make your changes, and submit a pull request.


