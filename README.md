# Technische oefening 

The instructions for the technical exercise are in [here](greenfield-project-java/README.md). As there is currently only 
a single exercise, navigate to **greenfield-project-java** for further instructions.

## initial setup

I firstly created the state bucket using a KMS key for this bucket, to save some costs I allowed the bucket key property.
Versioning was also enabled to be able to recover a previous state if needed.

A deploy role was made, only this role is allowed to use the kms key and access the state bucket. Trough CI/CD this role can be used to deploy.
To avoid local deployments especially on production this role should only be used by the CI/CD.
In a test environment or non-prod I am inclined to allow local deployments.
In this case I allowed my IAM use to assume this role.

These steps were all done manually, in an organisation this could be automated.
Cloudformation templates can be configured to automaticly create the needed resources with the right policies (state bucket, kms key and deploy role for each account)

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

## VPC deployment
Given the scope of this project, I did not carefully plan the IP range against a broader address space I used a simple, arbitrarily-sized VPC CIDR (10.20.0.0/16).

In a real multi-account environment with a Transit Gateway (or VPC peering) in play, this matters a lot more: CIDR ranges must be deliberately sized and non-overlapping across every VPC that could ever be connected, since overlapping ranges make routing between them impossible without NAT gymnastics.

AWS offers IPAM (IP Address Manager) to manage this centrally, but it comes with an ongoing per-CIDR/per-region cost that may not be justified for smaller organizations.

A lower-cost alternative I've used previously:
A DynamoDB table acting as a CIDR allocation registry tracking which ranges are already in use, and automatically provisioning the next free, correctly-sized block whenever a new account or VPC is created (e.g. as a step in an account-vending pipeline). It's less feature-rich than IPAM but covers the core need guaranteed non-overlapping ranges at effectively no extra cost