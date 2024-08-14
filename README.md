# EKS cluster with Terraform

## Overview

- Uses Terraform modules to create EKS, VPC, EC2 and RDS
- Uses EKS Blueprints module for K8S Addons
- Deploys kube-prometheus-stack with domain name and SSL cert
- Automatically creates ALB rules and Route 53 entries based on Ingress resources

## Architecture

![image](https://github.com/user-attachments/assets/0a7dff9b-5611-4ceb-b60d-068974fc7eec)

## TODOs

- parametrise inputs like domain name
