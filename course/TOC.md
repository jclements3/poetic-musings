# Table of Contents — Zero to Hero: DevSecOps & Cloud DevOps (Batch-10)

Source: `Batch-10 Syllabus.pdf` (35 pages) — DevOps Shack, Batch-10 | Recorded, complete content accessible from 15th June.

## Front matter

- Cover
- Success stories / testimonials
- Projects in DevOps BootCamp (Project-1 through Project-20 overview list)

## Module 1: Introduction to DevOps & DevSecOps

1. Introduction to DevOps and DevSecOps
2. Real-Time Corporate DevOps Workflow with Flow Diagram
3. DevOps Team Structure
4. Day-to-Day DevOps Activities
5. Deployment Strategies (Blue-Green, Rolling, Canary, Recreate, & more)

## Module 2: Linux & Shell Scripting

1. Introduction to Linux
2. Virtual Machines (VMs)
3. Essential Linux Commands
4. Package Management
5. File/Folder Permissions
6. User & Group Management
7. Process Management
8. Associate a New Elastic IP with An Existing Instance
9. Curl vs Wget Demo
10. Directory Structure
11. Shell Script Website Monitor Project
12. 10 Real-Time Shell Scripts with Demo
13. Linux Networking (interfaces, OSI model, routing, IP/subnetting, common commands)
14. Linux Troubleshooting
15. Shell Scripting Hands-on (variables, conditionals, loops, functions, arrays, regex, debugging, etc.)

## Module 3: Git

1. Introduction to Git
2. Version Control & Git Basics
3. Essential Git Concepts
4. Git Branch Management
5. Git Diff
6. Git Merge & Rebase
7. Stash & Pop
8. Cherry-Pick
9. Tags
10. Git Squash With Demo
11. Merge Conflicts
12. Git Revert
13. Git Reset (Hard/Soft/Mixed)
14. Git Errors & Resolutions
15. Corporate Branching Strategy
16. Interview Prep Documents (Comprehensive Guide, Interview Q&A, Errors & Troubleshooting, Scenario Based)

## Module 4: Build Tools

1. Build Tools & Project Structure
2. Maven Hands-on
3. NPM Hands-on
4. Building Multi-Tier Projects (Dotnet + MongoDB, NodeJS + MySQL, Python + Postgres)
5. Tomcat Server & Deploying Projects

## Module 5: CI/CD Tools

- CI/CD Tools Overview
- **Jenkins**
  1. Jenkins Setup, Configurations, Plugins
  2. Jenkins Jobs (Freestyle, Pipeline, Multibranch)
  3. Upstream & Downstream Jobs
  4. User Management
  5. Shared Libraries
  6. Parameters in Jenkins
  7. Webhooks for Auto Triggering Pipeline Jobs
  8. Integrations (SonarQube, Nexus, Docker, Kubernetes, Security tools)
  9. Jenkins Mail Notifications
  10. Jenkins Backups
  11. Jenkins Errors & Troubleshooting
  12. Post Actions
  13. Variables in Jenkins
  14. Scenario based Jenkins Implementations
  15. RBAC In Jenkins For User Management (Local LDAP Setup)
  16. Docker Containers As Jenkins Slave
  17. Integrating HashiCorp Vault in Jenkins
  18. Full Stack CI/CD Pipelines (10+ projects with Jenkins)
- **GitHub Actions**
  1. Complete Setup (runners, workflows, YAML pipeline)
  2. Full Stack CI/CD Pipelines [Project-1]
  3. Full Stack CI/CD Pipelines [Project-2]
- **GitLab CI/CD**
  1. Complete Setup (runners, `.gitlab-ci.yml`, YAML pipeline)
  2. Full Stack CI/CD Pipelines

## Module 6: SonarQube

1. Setting up SonarQube Locally, With Docker & In Kubernetes
3. Understanding Profiles & Rules
4. Advanced Third-Party Plugin Installation
5. Branch Analysis (Developer Edition Feature for Free)
6. Integrating with CI/CD Tools (Jenkins, GitHub Actions, GitLab CI/CD)
7. Generating and Exporting Reports in SonarQube (PDF, CSV, HTML)
8. Configure SonarQube Webhook
9. SonarQube Analysis with Maven (Code Coverage Enabled)
10. SonarQube Analysis with NodeJS Project (Code Coverage Enabled)
11. SonarQube Analysis with Python Project (Code Coverage Enabled)

## Module 7: Security Tools

1. Security Tools Overview
2. Trivy Setup & File System Scanning
3. OWASP Dependency Check Setup & Usage
4. Tools like Prowler, Dockle, OWASP ZAP
5. Security Tools Integrations With CI/CD
6. SBOM (Software Bill of Materials) Hands-On Usage
7. Checkov (IaC config file scanning)
8. Gitleaks (secrets/API key detection in source code)
9. HashiCorp Vault (secrets management, CI/CD integration)

## Module 8: Nexus Artifact Management

1. What are Artifacts? How to Store them in Nexus?
2. Setup Nexus Locally & via Docker
3. Understanding Nexus Structure
4. Nexus Cleanup Tasks
5. Configuring Repositories, Artifacts
6. Publishing Maven & NodeJS Artifacts via CI/CD Pipeline
7. Setup Private Docker Registry

## Module 9: Docker

**Containerization Deep Dive**
1. Virtualization vs Containerization
2. Docker Architecture
3. Understanding Docker Image, Dockerfile, Docker Container
4. Install & Setup Docker With Proper Permissions
5. Writing Optimized Dockerfiles
6. ADD vs COPY & ENTRYPOINT vs CMD
7. Most Used Docker Commands
8. Building Docker Images & Creating Containers
9. Private Docker Registry
10. Multi-Stage Dockerfiles
11. Docker Errors & Troubleshooting
12. Docker Compose with Project
13. Docker Networking & Volumes
14. Scenario Based Docker Implementations

**Docker Projects**
1. Java based monitoring project
2. DotNET based monitoring project
3. NodeJS based monitoring project
4. Python based monitoring project
5. Multi-Tier Java + MySQL project
6. Multi-Tier DotNET + MongoDB project
7. Multi-Tier NodeJS + MySQL project
8. Multi-Tier Python + Postgres project
9. Virtual Browser project (x2)

## Module 10: Kubernetes

1. Detailed Kubernetes Architecture
2. Deployments, Pods, Services, Secrets, ConfigMaps, Persistent Volumes, Storage Class
3. Service Types & Usage
4. Kubernetes Local Setup Using Kubeadm & ContainerD
5. Kubernetes Networking
6. RBAC (Role-Based Access Control) in Kubernetes
7. Highly Available K8s Cluster Setup Locally
8. Horizontal & Vertical Auto-Scaling & Rollback in K8s
9. Kubernetes Errors & Troubleshooting
10. Ingress Setup for App Deployed in K8s
11. Custom Domain Mapping for App Deployed in K8s
12. SSL Certificate Setup for App Deployed in K8s
13. HashiCorp Vault Dev & Production Setup
14. Helm Chart Complete Tutorial with Demo
15. ArgoCD Tutorial with Hands-On Project
16. Stateful Sets in Kubernetes (With Demo — MySQL as StatefulSet)
17. Service Mesh With Istio
18. ArgoCD (Understanding ArgoCD, CI/CD Using Jenkins + ArgoCD)

**Kubernetes Projects [With EKS, Local K8s]**
1. Kubernetes Multi-Tier Mega Project
2. Helm Chart Multi-Tier Mega Project
3. GitOps with ArgoCD
4. Blue-Green Deployment [Project-1]
5. Blue-Green Deployment [Project-2]
6. 11 Microservices Project Deployment
7. GitHub Actions CICD (AKS)
8. Multi-Tier Project With Stateful set
9. A Capstone Project

## Module 11: Azure DevOps

- Understanding Azure DevOps & How It's Different from Traditional DevOps
- Setting Up Azure Organisation
- **Core Services**: Azure Repos, Azure Pipelines, Azure Artifacts, Azure Kubernetes Service (AKS), Azure Container Registry (ACR)
- Creating Service Principal for Authentication in Pipelines
- **CI/CD Pipelines**
  1. CI/CD Pipelines to Deploy to Azure Kubernetes Service (AKS) — Classic & YAML
  2. Java Project Deploy to Webapps — Classic & YAML
  3. Multitier Java Project Deploy to AKS — Classic & YAML
  4. Multitier NodeJS + Database Project Deploy to Webapp — Classic & YAML

## Module 12: Infrastructure as Code (IaC)

**Terraform Deep Dive**
1. Infrastructure as Code Introduction
2. Understanding Terraform from Scratch
3. Terraform Setup
4. Terraform Credentials for AWS
5. Writing & Understanding Terraform Code (main.tf, variables.tf, outputs.tf, tfstate, tfvars)
6. Terraform Data Sources
7. Terraform Import
8. Terraform Provisioners
9. Terraform State Management with S3-Bucket
10. Terraform Modules
11. Terraform Modules Multi-Environment Project
12. Terraform Workspaces
13. EKS Creation with Terraform
14. Terraform with Jenkins
15. Corporate Terraform Project

**Ansible Deep Dive**
1. Ansible Introduction
2. Ansible Modules
3. Ansible Plays & Playbooks
4. Ansible Collections
5. Ansible Roles
6. Ansible with Jenkins
7. Ansible CI/CD Project
8. Ansible Vault
9. Ansible with Terraform Project
10. Ansible Static & Dynamic Inventory File

## Module 13: Monitoring

**Monitoring with Prometheus & Grafana**
1. Prometheus, Node Exporter, Black Box Exporter, Grafana Local Setup & Monitoring
2. Mail Notifications Based on Monitoring Project
3. Monitoring Tools Setup Using Docker
4. Kubernetes Node Monitoring Project
5. Application Monitoring in K8s Project
6. Grafana + GitHub Mini Project

## Module 14: Python For DevOps

- Python Introduction (why Python for DevOps, setup, scripts)
- Datatypes, Variables & Best Practices in Python
- Functions & Modules in Python
- Control Statements & Loops in Python
- File Handling in Python
- Python Socket Library
- JSON Manipulation in Python
- Database Basics
- Connecting to PostgreSQL
- Boto3 | AWS SDK for Python
- Docker SDK for Python
- Kubernetes With Python (kubernetes-client SDK, automating deployments)
