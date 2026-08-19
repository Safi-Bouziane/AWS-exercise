# Technische oefening

The instructions for the technical exercise are in [here](greenfield-project-java/README.md). As there is currently only
a single exercise, navigate to **greenfield-project-java** for further instructions.

## Architecture overview

```
Internet
  │
  ▼
ALB (public subnets, HTTPS via ACM, HTTP→HTTPS redirect)
  │
  ▼
Target group (instance type, fixed NodePort)
  │
  ▼
EKS worker nodes (private subnets) ── kube-proxy forwards to whichever
  │                                    node actually holds the pod
  ▼
App pods (Quarkus native, non-root)
```

- VPC with public subnets (ALB only) and private subnets (EKS nodes) across 3 AZs.
- EKS control plane API endpoint is **private only** deployment happens via CloudShell or a bastion, not directly from a local machine.
- Terraform state is stored remotely in S3 (KMS-encrypted, versioned), with access locked down to a dedicated IAM role.
- The application manifest is applied separately via `kubectl`, not through Terraform see [How to deploy to kubernetes](#how-to-deploy-to-kubernetes) for the reasoning.

## How to deploy infra

Set the correct profile
````
export AWS_PROFILE=terraform_deploy (can be different)
````

With the following entry in your config file
````
[profile terraform_deploy]
role_arn = arn:aws:iam::654654510727:role/terraform-deploy-role-safi
source_profile = default
region = eu-west-1
````

## How to deploy to kubernetes

````
aws eks update-kubeconfig --region eu-west-1 --name greenfield-dev
````

Important here to note that public access has been disabled, so to access the cluster a bastion or CloudShell can be used, as long as the correct network settings are being used.

````
kubectl apply -f greenfield-project.yaml
````

### Initial setup

I first created the state bucket using a KMS key for this bucket; to reduce costs, I enabled the S3 Bucket Key feature.
Versioning was also enabled to be able to recover a previous state if needed.

A deploy role was made, only this role is allowed to use the KMS key and access the state bucket. Through CI/CD this role can be used to deploy.
To avoid local deployments, especially on production, this role should only be used by the CI/CD.
In a test environment or non-prod I am inclined to allow local deployments.
In this case I allowed my IAM user to assume this role.

These steps were all done manually; in an organisation this could be automated.
CloudFormation templates can be configured to automatically create the needed resources with the right policies (state bucket, KMS key, and deploy role for each account).

Bucket policy:

````
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyInsecureTransport",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::safi-exercise-tfstate",
                "arn:aws:s3:::safi-exercise-tfstate/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        },
        {
            "Sid": "OnlyDeployRoleMayAccess",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::safi-exercise-tfstate",
                "arn:aws:s3:::safi-exercise-tfstate/*"
            ],
            "Condition": {
                "StringNotLike": {
                    "aws:PrincipalArn": "arn:aws:iam::654654510727:role/terraform-deploy-role-safi"
                }
            }
        }
    ]
}
````

Kms key policy:
````
{
	"Version": "2012-10-17",
	"Id": "key-consolepolicy-3",
	"Statement": [
		{
			"Sid": "Allow access for Key Administrators",
			"Effect": "Allow",
			"Principal": {
				"AWS": "arn:aws:iam::654654510727:role/terraform-deploy-role-safi"
			},
			"Action": [
				"kms:Create*",
				"kms:Describe*",
				"kms:Enable*",
				"kms:List*",
				"kms:Put*",
				"kms:Update*",
				"kms:Revoke*",
				"kms:Disable*",
				"kms:Get*",
				"kms:Delete*",
				"kms:TagResource",
				"kms:UntagResource",
				"kms:ScheduleKeyDeletion",
				"kms:CancelKeyDeletion",
				"kms:RotateKeyOnDemand"
			],
			"Resource": "*"
		},
		{
			"Sid": "Allow use of the key",
			"Effect": "Allow",
			"Principal": {
				"AWS": "arn:aws:iam::654654510727:role/terraform-deploy-role-safi"
			},
			"Action": [
				"kms:Encrypt",
				"kms:Decrypt",
				"kms:ReEncrypt*",
				"kms:GenerateDataKey*",
				"kms:DescribeKey"
			],
			"Resource": "*"
		},
		{
			"Sid": "Allow attachment of persistent resources",
			"Effect": "Allow",
			"Principal": {
				"AWS": "arn:aws:iam::654654510727:role/terraform-deploy-role-safi"
			},
			"Action": [
				"kms:CreateGrant",
				"kms:ListGrants",
				"kms:RevokeGrant"
			],
			"Resource": "*",
			"Condition": {
				"Bool": {
					"kms:GrantIsForAWSResource": "true"
				}
			}
		}
	]
}
````

### VPC deployment
Given the scope of this project, I did not carefully plan the IP range against a broader address space; I used a simple, arbitrarily-sized VPC CIDR (10.20.0.0/16).

In a real multi-account environment with a Transit Gateway (or VPC peering) in play, this matters a lot more: CIDR ranges must be deliberately sized and non-overlapping across every VPC that could ever be connected, since overlapping ranges make routing between them impossible without NAT gymnastics.

AWS offers IPAM (IP Address Manager) to manage this centrally, but it comes with an ongoing per-CIDR/per-region cost that may not be justified for smaller organizations.

A lower-cost alternative I've used previously:
A DynamoDB table acting as a CIDR allocation registry, tracking which ranges are already in use, and automatically provisioning the next free, correctly-sized block whenever a new account or VPC is created (e.g. as a step in an account-vending pipeline). It's less feature-rich than IPAM but covers the core need guaranteed non-overlapping ranges at effectively no extra cost.

### EKS

Here it is important to highlight that `enable_irsa` was set to true.
The idea here is to create a role for each ServiceAccount and set the permissions an application needs on that role.
My Kubernetes knowledge is limited, but my understanding is that a pod can be linked to a ServiceAccount, and IRSA lets us attach an IAM role to that ServiceAccount when the application needs AWS access.

Public access to the EKS API endpoint is disabled, so the cluster's control plane is only reachable from within the AWS network (e.g. via CloudShell or a bastion) not from the public internet. The application itself is still reachable publicly, through the ALB described below.

### Load balancing

Traffic reaches the app via an internet-facing ALB → target group (instance type) → the EKS node group's Auto Scaling Group, on a fixed NodePort (30080).

I considered the AWS Load Balancer Controller (an Ingress-based approach that runs inside the cluster and tracks individual pod IPs as targets, updating automatically as pods reschedule), but chose a plain Terraform-provisioned ALB for this exercise's scope it's simpler to reason about and explain for a single application.

The trade-off: NodePort requires a manually chosen port per Service, and the ALB's health check can only confirm a *node* is reachable on that port, not that a *pod* is specifically healthy there (kube-proxy handles that redirection invisibly, cluster-wide). A second application would need its own NodePort, target group, and listener rule. The Ingress Controller approach avoids that manual coordination new Ingress rules reconfigure the same ALB automatically at the cost of more moving parts (an IRSA role for the controller, a Helm release, and a controller pod to operate).

Security groups are scoped tightly: the ALB only accepts inbound 80/443 from the internet, and only the ALB's security group is permitted to reach the nodes on the app's NodePort nothing else can reach the nodes directly.

The Auto Scaling Group behind the node group is attached directly to the target group (`aws_autoscaling_attachment`), so nodes register/deregister automatically as the group scales no re-apply needed when node count changes.

### HTTPS

An ACM certificate for `eks.safidesafi.be` is provisioned via Terraform using DNS validation. Since DNS is hosted externally at Combell rather than Route53, the validation CNAME record (and the CNAME pointing the domain itself at the ALB) are added manually `terraform apply` polls ACM and waits for validation to complete before continuing.

Port 80 redirects to port 443 (HTTP 301) rather than serving traffic directly. The HTTPS listener uses the `ELBSecurityPolicy-TLS13-1-2-2021-06` policy, enforcing TLS 1.2 as a minimum with TLS 1.3 support, rather than AWS's older default policy.

### Application manifest

The Deployment runs as non-root (UID 1001),and all Linux capabilities dropped.

Readiness (`/q/health/ready`) and liveness (`/q/health/live`) probes are wired to Quarkus's built-in health endpoints. Resource requests/limits are set on the container to prevent a single pod from starving a node of CPU/memory.

### improvements

Separate stack per component (VPC, EKS, ALB, ECR) to decrease blast radius `terraform_remote_state` data sources or SSM parameters would be needed to cross-reference outputs between stacks.

I was not able to provide a CI/CD setup in the time limit of 4h. Here I would create a separate role that can push to ECR and assume the deploy role. This role would then be used by the CI/CD